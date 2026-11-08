#if os(macOS) && arch(arm64)

  import Containerization
  import Foundation

  import ThistleSupport

  /// Locates and launches the guest vsock→TCP forwarder inside the container.
  @available(macOS 26.0, *)
  enum GuestForwarder {
    static func hostBinaryURL() throws -> URL {
      if let bundled = Bundle.main.url(
        forResource: EngineIdentity.guestForwarderResourceName,
        withExtension: nil,
        subdirectory: "guest-forwarder/linux-arm64")
      {
        return bundled
      }

      // LaunchAgent executable lives in Contents/MacOS; Resources is sibling.
      let exec = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
      let resources = exec.deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/guest-forwarder/linux-arm64", isDirectory: true)
      let candidate = resources.appendingPathComponent(EngineIdentity.guestForwarderResourceName)
      if FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
        return candidate
      }

      // Dev fallback: workspace Resources after `make guest-forwarder`.
      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      let dev = cwd.appendingPathComponent(
        "Resources/guest-forwarder/linux-arm64/\(EngineIdentity.guestForwarderResourceName)")
      if FileManager.default.isExecutableFile(atPath: dev.path(percentEncoded: false)) {
        return dev
      }

      throw EngineError.guestForwarderMissing(candidate.path(percentEncoded: false))
    }

    static func shareMount(hostBinary: URL) -> Mount {
      Mount.share(
        source: hostBinary.deletingLastPathComponent().path(percentEncoded: false),
        destination: EngineIdentity.guestForwarderMount,
        options: ["ro"]
      )
    }

    static func start(on container: LinuxContainer) async throws -> LinuxProcess {
      let guestBinary =
        "\(EngineIdentity.guestForwarderMount)/\(EngineIdentity.guestForwarderResourceName)"
      let process = try await container.exec("thistle-api-forwarder") { config in
        config.arguments = [
          guestBinary,
          "\(EngineIdentity.apiVsockPort)",
          "\(EngineIdentity.guestPort)",
        ]
        config.workingDirectory = "/"
      }
      try await process.start()
      return process
    }

    /// Wait until the host can dial the guest vsock listener.
    static func waitUntilAccepting(
      dial: @escaping @Sendable (UInt32) async throws -> FileHandle,
      timeout: Duration = .seconds(30)
    ) async throws {
      let deadline = ContinuousClock.now + timeout
      var lastError: Error = EngineError.guestForwarderFailed("timed out waiting for vsock listener")
      while ContinuousClock.now < deadline {
        do {
          let handle = try await dial(EngineIdentity.apiVsockPort)
          try handle.close()
          return
        } catch {
          lastError = error
          try await Task.sleep(for: .milliseconds(100))
        }
      }
      throw EngineError.guestForwarderFailed(String(describing: lastError))
    }
  }

#endif
