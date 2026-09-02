#if os(macOS) && arch(arm64)

  import Containerization
  import ContainerizationError
  import ContainerizationEXT4
  import ContainerizationExtras
  import Foundation
  import SystemPackage

  import ThistleSupport

  @available(macOS 26.0, *)
  final class Engine: @unchecked Sendable {
    private var manager: ContainerManager
    private var container: LinuxContainer
    let baseURL: URL
    let imageDigest: String

    private init(
      manager: ContainerManager, container: LinuxContainer, baseURL: URL, imageDigest: String
    ) {
      self.manager = manager
      self.container = container
      self.baseURL = baseURL
      self.imageDigest = imageDigest
    }

    @concurrent
    static func start(
      forcePull: Bool = false,
      onProgress: @escaping @Sendable (EnginePhase) -> Void = { _ in }
    ) async throws -> Engine {
      try Paths.ensureDirectories()
      invalidateStaleCaches()

      onProgress(.kernel)
      let kernelURL = try await KernelManager.ensureKernel(
        explicitPath: nil, onProgress: onProgress)
      try Task.checkCancellation()
      let kernel = Kernel(path: kernelURL, platform: .linuxArm)
      await Task.yield()

      onProgress(.pulling)
      var manager = try await ContainerManager(
        kernel: kernel,
        initfsReference: EngineIdentity.initfs,
        root: Paths.appRoot,
        network: try VmnetNetwork(),
        rosetta: false
      )

      let imageRef: Containerization.Image
      if forcePull {
        imageRef = try await manager.imageStore.pull(reference: EngineIdentity.image)
        try? FileManager.default.removeItem(at: Paths.rootfs(for: EngineIdentity.image))
      } else {
        imageRef = try await manager.imageStore.get(
          reference: EngineIdentity.image, pull: true)
      }
      try Task.checkCancellation()

      invalidateRootfsIfNeeded(digest: imageRef.digest)
      await Task.yield()

      onProgress(.unpacking)
      let rootfsURL = Paths.rootfs(for: EngineIdentity.image)
      let rootfs: Containerization.Mount
      do {
        rootfs = try await unpackRootfs(image: imageRef, at: rootfsURL)
      } catch {
        try? FileManager.default.removeItem(at: rootfsURL)
        throw error
      }
      try Task.checkCancellation()

      try? manager.delete(EngineIdentity.containerID)

      let writable = try makeEmptyExt4(at: Paths.writable, size: 1.gib())
      let container = try await manager.create(
        EngineIdentity.containerID,
        image: imageRef,
        rootfs: rootfs,
        writableLayer: writable,
        networking: true
      ) { config in
        config.cpus = EngineIdentity.cpus
        config.memoryInBytes = EngineIdentity.memoryMiB.mib()
        var env = config.process.environmentVariables
        setEnv(&env, "LIBREOFFICE_AUTO_START", "true")
        setEnv(&env, "CHROMIUM_AUTO_START", "true")
        config.process.environmentVariables = env
      }

      guard let iface = container.config.interfaces.first else {
        try? manager.delete(EngineIdentity.containerID)
        throw EngineError.missingNetworkInterface
      }
      let ip = iface.ipv4Address.address.description
      guard let baseURL = URL(string: "http://\(ip):\(EngineIdentity.guestPort)") else {
        try? manager.delete(EngineIdentity.containerID)
        throw EngineError.missingNetworkInterface
      }

      do {
        onProgress(.booting)
        await Task.yield()
        try await container.create()
        try await container.start()

        onProgress(.waitingForAPI)
        await Task.yield()
        try await GotenbergClient.waitUntilHealthy(baseURL: baseURL)
      } catch {
        try? await container.stop()
        try? manager.delete(EngineIdentity.containerID)
        try? FileManager.default.removeItem(at: Paths.writable)
        try? FileManager.default.removeItem(at: Paths.runtimeState)
        throw error
      }

      let state = RuntimeState(baseURL: baseURL.absoluteString)
      try JSONEncoder().encode(state).write(to: Paths.runtimeState, options: .atomic)

      try EngineGeneration(
        schema: EngineIdentity.cacheSchema,
        kernelVersion: EngineIdentity.kernelVersion,
        initfs: EngineIdentity.initfs,
        image: EngineIdentity.image,
        imageDigest: imageRef.digest,
        unpackedDigest: imageRef.digest
      ).save()

      return Engine(
        manager: manager, container: container, baseURL: baseURL, imageDigest: imageRef.digest)
    }

    @concurrent
    func stop() async throws {
      var firstError: Error?
      do {
        try await container.stop()
      } catch {
        firstError = error
      }
      do {
        try manager.delete(EngineIdentity.containerID)
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
      try? FileManager.default.removeItem(at: Paths.runtimeState)
      try? FileManager.default.removeItem(at: Paths.writable)
      if let firstError {
        throw firstError
      }
    }

    static func pullImage() async throws {
      try Paths.ensureDirectories()
      let store = try ImageStore(path: Paths.appRoot)
      _ = try await store.pull(reference: EngineIdentity.image)
      try? FileManager.default.removeItem(at: Paths.rootfs(for: EngineIdentity.image))
    }

    private static func invalidateStaleCaches() {
      let gen = EngineGeneration.load()
      if gen?.schema != EngineIdentity.cacheSchema {
        try? FileManager.default.removeItem(at: Paths.rootfs(for: EngineIdentity.image))
        try? FileManager.default.removeItem(at: Paths.initfs)
      }
      if gen?.initfs != EngineIdentity.initfs {
        try? FileManager.default.removeItem(at: Paths.initfs)
      }
      if gen?.image != EngineIdentity.image {
        try? FileManager.default.removeItem(at: Paths.rootfs(for: EngineIdentity.image))
      }
    }

    private static func invalidateRootfsIfNeeded(digest: String) {
      let gen = EngineGeneration.load()
      if gen?.unpackedDigest != digest {
        try? FileManager.default.removeItem(at: Paths.rootfs(for: EngineIdentity.image))
      }
    }

    private static func unpackRootfs(image: Containerization.Image, at url: URL) async throws
      -> Containerization.Mount
    {
      do {
        let unpacker = EXT4Unpacker(capacityInBytes: 8.gib())
        var mount = try await unpacker.unpack(image, for: .current, at: url)
        if !mount.options.contains("ro") {
          mount.options.append("ro")
        }
        return mount
      } catch let err as ContainerizationError where err.code == .exists {
        return .block(
          format: "ext4",
          source: url.path(percentEncoded: false),
          destination: "/",
          options: ["ro"]
        )
      }
    }

    private static func setEnv(_ env: inout [String], _ key: String, _ value: String) {
      env.removeAll { $0.hasPrefix("\(key)=") }
      env.append("\(key)=\(value)")
    }

    private static func makeEmptyExt4(at url: URL, size: UInt64) throws -> Containerization.Mount {
      let path = url.path(percentEncoded: false)
      if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.removeItem(at: url)
      }
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let formatter = try EXT4.Formatter(FilePath(path), minDiskSize: size)
      try formatter.close()
      return .block(format: "ext4", source: path, destination: "/", options: [])
    }

  }

#endif
