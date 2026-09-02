#if os(macOS) && arch(arm64)

  import ContainerizationArchive
  import Foundation

  import ThistleSupport

  enum KernelManager {
    private static let defaultKernelURL =
      "https://github.com/kata-containers/kata-containers/releases/download/3.26.0/kata-static-3.26.0-arm64.tar.zst"
    private static let defaultKernelPathInTarball =
      "opt/kata/share/kata-containers/vmlinux.container"

    static func invalidateIfStale() {
      let gen = EngineGeneration.load()
      if gen?.kernelVersion != EngineIdentity.kernelVersion {
        try? FileManager.default.removeItem(at: Paths.kernel)
      }
    }

    @concurrent
    static func ensureKernel(
      explicitPath: String?,
      onProgress: @escaping @Sendable (EnginePhase) -> Void = { _ in }
    ) async throws -> URL {
      if let explicitPath {
        let url = URL(fileURLWithPath: explicitPath)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
          throw EngineError.kernelNotFound(explicitPath)
        }
        return url
      }

      invalidateIfStale()
      let kernelPath = Paths.kernel
      if FileManager.default.fileExists(atPath: kernelPath.path(percentEncoded: false)) {
        return kernelPath
      }

      try FileManager.default.createDirectory(
        at: Paths.kernelDirectory, withIntermediateDirectories: true)

      let tarballPath = Paths.kernelDirectory.appendingPathComponent("kata.tar.zst")
      if !usableTarballExists(at: tarballPath) {
        onProgress(.downloadingKernel)
        try await download(from: defaultKernelURL, to: tarballPath)
      }

      onProgress(.extractingKernel)
      do {
        try extractKernel(
          from: tarballPath, kernelPathInTarball: defaultKernelPathInTarball, to: kernelPath)
      } catch {
        // A complete-sized but corrupt partial download must not poison every later start.
        try? FileManager.default.removeItem(at: tarballPath)
        throw error
      }
      try? FileManager.default.removeItem(at: tarballPath)
      return kernelPath
    }

    private static func usableTarballExists(at url: URL) -> Bool {
      guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
        let size = values.fileSize
      else {
        return false
      }
      // Incomplete leftovers are typically tiny; a finished Kata arm64 tarball is hundreds of MB.
      return size > 50_000_000
    }

    private static func download(from urlString: String, to destination: URL) async throws {
      guard let url = URL(string: urlString) else {
        throw EngineError.kernelDownloadFailed("invalid URL: \(urlString)")
      }
      do {
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
          throw EngineError.kernelDownloadFailed("HTTP \(http.statusCode)")
        }
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temp, to: destination)
      } catch let error as EngineError {
        throw error
      } catch {
        throw EngineError.kernelDownloadFailed(error.localizedDescription)
      }
    }

    private static func extractKernel(
      from tarball: URL, kernelPathInTarball: String, to destination: URL
    ) throws {
      do {
        try extractKernelWithTar(
          from: tarball, kernelPathInTarball: kernelPathInTarball, to: destination)
      } catch {
        let tarError = error
        do {
          try extractKernelWithArchiveReader(
            from: tarball, kernelPathInTarball: kernelPathInTarball, to: destination)
        } catch {
          throw EngineError.kernelExtractFailed(
            "tar failed (\(EngineError.message(for: tarError))); fallback failed (\(EngineError.message(for: error)))"
          )
        }
      }
    }

    // Stream a single member out of the zstd tarball. ArchiveReader decompresses the whole
    // Kata static archive first, which looks like a hang on "Preparing kernel".
    private static func extractKernelWithTar(
      from tarball: URL, kernelPathInTarball: String, to destination: URL
    ) throws {
      let workDir = Paths.kernelDirectory.appendingPathComponent("extract")
      try? FileManager.default.removeItem(at: workDir)
      try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: workDir) }

      try runTar(arguments: [
        "-xf", tarball.path(percentEncoded: false),
        "-C", workDir.path(percentEncoded: false),
        kernelPathInTarball,
      ])

      var extracted = workDir.appending(path: kernelPathInTarball)
      if let link = try? FileManager.default.destinationOfSymbolicLink(
        atPath: extracted.path(percentEncoded: false))
      {
        let target = URL(filePath: kernelPathInTarball).deletingLastPathComponent()
          .appending(path: link).standardized.relativePath
        try runTar(arguments: [
          "-xf", tarball.path(percentEncoded: false),
          "-C", workDir.path(percentEncoded: false),
          target,
        ])
        extracted = workDir.appending(path: target)
      }

      guard FileManager.default.fileExists(atPath: extracted.path(percentEncoded: false)) else {
        throw EngineError.kernelExtractFailed("tar did not write \(kernelPathInTarball)")
      }
      if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: extracted, to: destination)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: destination.path(percentEncoded: false)
      )
    }

    private static func runTar(arguments: [String]) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      process.arguments = arguments
      let stderr = Pipe()
      process.standardOutput = FileHandle.nullDevice
      process.standardError = stderr
      do {
        try process.run()
      } catch {
        throw EngineError.kernelExtractFailed("could not launch tar: \(error.localizedDescription)")
      }
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let message =
          String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
        throw EngineError.kernelExtractFailed(message)
      }
    }

    private static func extractKernelWithArchiveReader(
      from tarball: URL, kernelPathInTarball: String, to destination: URL
    ) throws {
      var target = kernelPathInTarball
      var reader = try ArchiveReader(file: tarball)
      var (entry, data) = try reader.extractFile(path: target)

      if entry.fileType == .symbolicLink, let symlinkRelative = entry.symlinkTarget {
        reader = try ArchiveReader(file: tarball)
        let symlinkTarget = URL(filePath: target).deletingLastPathComponent().appending(
          path: symlinkRelative)
        target = symlinkTarget.standardized.relativePath
        let (_, targetData) = try reader.extractFile(path: target)
        data = targetData
      }

      try data.write(to: destination, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: destination.path(percentEncoded: false)
      )
    }
  }

#endif
