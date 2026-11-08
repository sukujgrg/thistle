#if os(macOS) && arch(arm64)

  import Darwin
  import Foundation
  import ServiceManagement

  import ThistleSupport

  enum EngineAgent {
    private static var service: SMAppService {
      SMAppService.agent(plistName: EngineIdentity.agentPlist)
    }

    static func register() throws {
      try Paths.ensureDirectories()
      let helper = Bundle.main.bundleURL
        .appendingPathComponent("Contents/MacOS/ThistleEngine", isDirectory: false)
        .path(percentEncoded: false)
      guard FileManager.default.isExecutableFile(atPath: helper) else {
        throw EngineError.agentUnavailable("helper missing at \(helper)")
      }

      // Drop obsolete ~/Library LaunchAgents only. Never bootout the live
      // SMAppService job — that shares this label and breaks XPC.
      removeLegacyLaunchAgentPlist()

      switch service.status {
      case .enabled:
        try ensureJobRunning()
        return
      case .requiresApproval:
        throw EngineError.agentNeedsApproval
      case .notRegistered, .notFound:
        break
      @unknown default:
        break
      }

      do {
        try service.register()
      } catch {
        if service.status == .requiresApproval {
          throw EngineError.agentNeedsApproval
        }
        throw EngineError.agentUnavailable(error.localizedDescription)
      }

      switch service.status {
      case .enabled:
        try ensureJobRunning()
      case .requiresApproval:
        throw EngineError.agentNeedsApproval
      default:
        throw EngineError.agentUnavailable("engine helper is not enabled")
      }
    }

    static func unload() {
      removeLegacyLaunchAgentPlist()
      // Boot out before unregister so a stale Mach bootstrap cannot linger.
      _ = try? launchctl(["bootout", domainLabel])
      try? service.unregister()
      let deadline = Date().addingTimeInterval(5)
      while isLoaded, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }
    }

    static var isLoaded: Bool {
      if service.status == .enabled { return true }
      // Legacy ~/Library/LaunchAgents bootstrap from before SMAppService.
      return isJobPrinted
    }

    static var needsApproval: Bool {
      service.status == .requiresApproval
    }

    static func openLoginItemsSettings() {
      SMAppService.openSystemSettingsLoginItems()
    }

    /// Shape of the LaunchAgent plist shipped in Contents/Library/LaunchAgents.
    static func configuration(
      bundleProgram: String = "Contents/MacOS/ThistleEngine",
      bundleIdentifier: String
    ) -> [String: Any] {
      [
        "Label": EngineIdentity.xpcService,
        "BundleProgram": bundleProgram,
        "AssociatedBundleIdentifiers": [bundleIdentifier],
        "MachServices": [EngineIdentity.xpcService: true],
      ]
    }

    private static var domainLabel: String { "gui/\(getuid())/\(EngineIdentity.xpcService)" }

    private static var isJobPrinted: Bool {
      (try? launchctl(["print", domainLabel]).status) == 0
    }

    private static var legacyLaunchAgentPlist: URL {
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
        .appendingPathComponent(EngineIdentity.agentPlist)
    }

    private static func removeLegacyLaunchAgentPlist() {
      try? FileManager.default.removeItem(at: legacyLaunchAgentPlist)
    }

    /// SMAppService can report `.enabled` while the job is not loaded (for example
    /// after a mistaken bootout). Kickstart, or re-register if needed.
    private static func ensureJobRunning() throws {
      if isJobPrinted { return }
      _ = try? launchctl(["kickstart", "-k", domainLabel])
      let deadline = Date().addingTimeInterval(3)
      while !isJobPrinted, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }
      if isJobPrinted { return }

      try? service.unregister()
      do {
        try service.register()
      } catch {
        if service.status == .requiresApproval {
          throw EngineError.agentNeedsApproval
        }
        throw EngineError.agentUnavailable(error.localizedDescription)
      }
      guard service.status == .enabled else {
        if service.status == .requiresApproval {
          throw EngineError.agentNeedsApproval
        }
        throw EngineError.agentUnavailable("engine helper is not enabled")
      }
      _ = try? launchctl(["kickstart", "-k", domainLabel])
      let retryDeadline = Date().addingTimeInterval(3)
      while !isJobPrinted, Date() < retryDeadline {
        Thread.sleep(forTimeInterval: 0.1)
      }
      if !isJobPrinted {
        throw EngineError.agentUnavailable("engine helper did not start")
      }
    }

    private static func launchctl(_ arguments: [String]) throws -> (status: Int32, output: String) {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
      proc.arguments = arguments
      let pipe = Pipe()
      proc.standardOutput = pipe
      proc.standardError = pipe
      try proc.run()
      proc.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
  }

  final class EngineXPCClient: @unchecked Sendable {
    private var connection: NSXPCConnection?

    func connect() throws {
      try open(register: true)
    }

    func stopIfLoaded() async throws {
      guard EngineAgent.isLoaded else { return }
      try open(register: false)
      try await call(timeout: .seconds(30)) { $0.stopEngine(reply: $1) }
    }

    private func open(register: Bool) throws {
      if connection != nil { return }
      if register {
        try EngineAgent.register()
      } else if !EngineAgent.isLoaded {
        throw EngineError.agentUnavailable("engine helper is not running")
      }
      let connection = NSXPCConnection(machServiceName: EngineIdentity.xpcService)
      connection.remoteObjectInterface = NSXPCInterface(with: EngineXPCProtocol.self)
      connection.invalidationHandler = { [weak self] in
        self?.connection = nil
      }
      connection.interruptionHandler = { [weak self] in
        self?.connection = nil
      }
      connection.resume()
      self.connection = connection
    }

    func status() async throws -> EngineStatusDTO {
      let data: Data = try await withXPCReply(timeout: .seconds(5)) { xpc, complete in
        xpc.fetchStatus { data, error in
          if let error {
            complete(.failure(EngineError.operationFailed(error)))
          } else if let data {
            complete(.success(data))
          } else {
            complete(.failure(EngineError.agentUnavailable("empty status")))
          }
        }
      }
      let dto = try JSONDecoder().decode(EngineStatusDTO.self, from: data)
      if dto.protocolVersion != EngineIdentity.protocolVersion {
        throw EngineError.protocolMismatch(dto.protocolVersion)
      }
      return dto
    }

    func start() async throws {
      try await call(timeout: .seconds(5)) { $0.startEngine(reply: $1) }
    }

    func stop() async throws {
      try await call(timeout: .seconds(30)) { $0.stopEngine(reply: $1) }
    }

    func restart() async throws {
      try await call(timeout: .seconds(5)) { $0.restartEngine(reply: $1) }
    }

    func refreshImage() async throws {
      try await call(timeout: .seconds(5)) { $0.refreshImage(reply: $1) }
    }

    func reset() async throws {
      try await call(timeout: .seconds(30)) { $0.resetEngine(reply: $1) }
    }

    func clearLogs() async throws {
      try await call(timeout: .seconds(5)) { $0.clearLogs(reply: $1) }
    }

    func submit(jobID: String, path: String, fields: [MultipartField], files: [FileRefDTO])
      async throws -> JobResultDTO
    {
      let fieldsJSON = try JSONEncoder().encode(fields)
      let filesJSON = try JSONEncoder().encode(files)
      let data: Data = try await withXPCReply(timeout: .seconds(300)) { xpc, complete in
        xpc.submitJob(jobID: jobID, path: path, fieldsJSON: fieldsJSON, filesJSON: filesJSON) {
          data, error in
          if let error {
            complete(.failure(EngineError.operationFailed(error)))
          } else if let data {
            complete(.success(data))
          } else {
            complete(.failure(EngineError.agentUnavailable("empty job result")))
          }
        }
      }
      return try JSONDecoder().decode(JobResultDTO.self, from: data)
    }

    private func call(
      timeout: Duration,
      _ body: @escaping @Sendable (EngineXPCProtocol, @escaping @Sendable (String?) -> Void) -> Void
    ) async throws {
      let _: Void = try await withXPCReply(timeout: timeout) { xpc, complete in
        body(xpc) { error in
          if let error {
            complete(.failure(EngineError.operationFailed(error)))
          } else {
            complete(.success(()))
          }
        }
      }
    }

    private func withXPCReply<T: Sendable>(
      timeout: Duration,
      _ operation:
        @escaping @Sendable (
          EngineXPCProtocol, @escaping @Sendable (Result<T, Error>) -> Void
        ) -> Void
    ) async throws -> T {
      try connect()
      return try await withReplyTimeout(timeout) { [weak self] complete in
        guard let self, let connection = self.connection else {
          complete(.failure(EngineError.agentUnavailable("no connection")))
          return
        }
        let object = connection.remoteObjectProxyWithErrorHandler { error in
          complete(.failure(EngineError.agentUnavailable(error.localizedDescription)))
        }
        guard let proxy = object as? EngineXPCProtocol else {
          complete(.failure(EngineError.agentUnavailable("no connection")))
          return
        }
        operation(proxy, complete)
      }
    }
  }

  private func withReplyTimeout<T: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
  ) async throws -> T {
    // A task-group race cannot time out an XPC continuation that never resumes:
    // leaving the group still waits for that child. Resolve one shared gate instead.
    let gate = ReplyGate<T>()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        gate.install(continuation)
        operation { result in
          gate.resolve(result)
        }
        gate.startTimeout(after: timeout)
      }
    } onCancel: {
      gate.resolve(.failure(CancellationError()))
    }
  }

  private final class ReplyGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
      lock.lock()
      if let result = pendingResult {
        pendingResult = nil
        lock.unlock()
        continuation.resume(with: result)
        return
      }
      self.continuation = continuation
      lock.unlock()
    }

    func startTimeout(after timeout: Duration) {
      let task = Task { [weak self] in
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        self?.resolve(
          .failure(EngineError.agentUnavailable("timed out waiting for the engine helper")))
      }
      lock.lock()
      if finished {
        lock.unlock()
        task.cancel()
        return
      }
      timeoutTask = task
      lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>) {
      lock.lock()
      guard !finished else {
        lock.unlock()
        return
      }
      finished = true
      let continuation = continuation
      self.continuation = nil
      if continuation == nil {
        pendingResult = result
      }
      let timeoutTask = timeoutTask
      self.timeoutTask = nil
      lock.unlock()

      timeoutTask?.cancel()
      continuation?.resume(with: result)
    }
  }

#endif
