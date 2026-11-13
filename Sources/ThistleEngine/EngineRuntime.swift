#if os(macOS) && arch(arm64)

  import Darwin
  import Foundation

  import ThistleSupport

  actor EngineRuntime {
    private enum Phase: Equatable {
      case idle
      case starting(progress: EnginePhase?, operation: String?)
      case running
      case failed(String)

      var label: String {
        switch self {
        case .idle:
          return "Stopped"
        case .starting(let progress, let operation):
          if let progress { return progress.label }
          return operation ?? "Starting"
        case .running:
          return "Running"
        case .failed:
          return "Failed"
        }
      }

      var lifecycle: EngineLifecyclePhase {
        switch self {
        case .idle: return .idle
        case .starting: return .starting
        case .running: return .running
        case .failed: return .failed
        }
      }
    }

    private var engine: Engine?
    private var startTask: Task<Engine, Error>?
    private var operationTask: Task<Void, Never>?
    private var bootToken: UUID?
    private var phase: Phase = .idle
    private var logs: [EngineLogEntry] = []
    private var idleTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    // Lives for the helper process, not the guest. stop() cancels the
    // watchdog, but a failed boot still has to cap engine.log.
    private var rotateTask: Task<Void, Never>?
    private var recoverCount = 0
    private var healthFailureStreak = 0
    private var activeSubmits = 0
    private var generationDigest: String?
    private var gotenbergVersion: String?
    private let client = GotenbergClient()

    init() {
      rotateTask = Task {
        while !Task.isCancelled {
          try? await Task.sleep(for: EngineIdentity.watchdog)
          guard !Task.isCancelled else { return }
          EngineLogFile.rotateIfNeeded()
        }
      }
    }

    func status() -> EngineStatusDTO {
      EngineStatusDTO(
        phase: phase.lifecycle.rawValue,
        phaseLabel: phase.label,
        guestURL: engine?.baseURL.absoluteString,
        failedMessage: failedMessage,
        logs: logs,
        imageDigest: engine?.imageDigest ?? cachedImageDigest(),
        gotenbergVersion: gotenbergVersion
      )
    }

    func requestStart() {
      if engine != nil || startTask != nil || operationTask != nil { return }
      recoverCount = 0
      healthFailureStreak = 0
      _ = beginStart(forcePull: false)
    }

    func requestRestart() {
      guard startTask == nil, operationTask == nil else { return }
      phase = .starting(progress: nil, operation: "Restarting engine")
      log("Restarting engine")
      operationTask = Task {
        try? await self.restart()
        await self.finishOperation()
      }
    }

    func requestRefreshImage() {
      guard startTask == nil, operationTask == nil else { return }
      phase = .starting(progress: nil, operation: "Refreshing image")
      log("Refreshing image")
      operationTask = Task {
        try? await self.refreshImage()
        await self.finishOperation()
      }
    }

    func start() async throws {
      requestStart()
      if let startTask {
        _ = try await startTask.value
      }
    }

    func stop(setIdle: Bool = true, logStop: Bool = true) async {
      if setIdle {
        phase = .starting(progress: nil, operation: "Stopping engine")
      }
      let pendingStart = startTask
      bootToken = nil
      pendingStart?.cancel()
      idleTask?.cancel()
      watchdogTask?.cancel()
      idleTask = nil
      watchdogTask = nil
      recoverCount = 0
      if let pendingStart {
        _ = try? await pendingStart.value
      }
      startTask = nil
      let current = engine
      engine = nil
      gotenbergVersion = nil
      if let current {
        try? await current.stop()
      }
      try? FileManager.default.removeItem(at: Paths.runtimeState)
      healthFailureStreak = 0
      if setIdle {
        phase = .idle
      }
      if logStop {
        log("Engine stopped")
      }
    }

    func restart() async throws {
      await stop(setIdle: false, logStop: false)
      // Bypass requestStart's operationTask gate so restart can boot while
      // the serialized operation that invoked us is still marked in-flight.
      recoverCount = 0
      healthFailureStreak = 0
      _ = try await beginStart(forcePull: false).value
    }

    func refreshImage() async throws {
      await stop(setIdle: false, logStop: false)
      phase = .starting(progress: nil, operation: "Refreshing image")
      do {
        try await Engine.pullImage()
        _ = try await ensureEngine(forcePull: false)
      } catch {
        fail(error)
        throw error
      }
    }

    func reset() async throws {
      guard startTask == nil, operationTask == nil else {
        throw EngineError.operationFailed("Engine is busy. Try again when the current operation finishes.")
      }
      phase = .starting(progress: nil, operation: "Resetting engine")
      await stop(setIdle: false, logStop: false)
      log("Resetting engine caches")
      do {
        try Paths.resetCaches()
        try Paths.ensureDirectories()
        EngineLogFile.clear()
        generationDigest = nil
        phase = .idle
        log("Engine reset")
      } catch {
        EngineLogFile.clear()
        fail(error)
        throw error
      }
    }

    func submit(jobID: String, path: String, fields: [MultipartField], files: [FileRefDTO])
      async throws -> JobResultDTO
    {
      let running = try await ensureEngine(forcePull: false)
      _ = path
      _ = fields
      if let issue = GotenbergRequirement.issue(version: gotenbergVersion) {
        throw EngineError.operationFailed(
          issue + " Use Refresh Image to update the built-in engine.")
      }
      touchIdle()
      activeSubmits += 1
      defer { activeSubmits -= 1 }
      let trace = HTTPTrace()
      let result: GotenbergClient.Response
      do {
        result = try await client.submit(
          baseURL: running.baseURL, path: path, fields: fields, files: files, trace: trace)
        // A finished convert is stronger liveness than /health.
        recoverCount = 0
        healthFailureStreak = 0
      } catch {
        flush(trace)
        log(EngineError.message(for: error))
        throw error
      }
      flush(trace)
      return try result.jobResult(jobID: jobID)
    }

    private func ensureEngine(forcePull: Bool) async throws -> Engine {
      if let engine, startTask == nil {
        touchIdle()
        return engine
      }
      if let startTask {
        return try await startTask.value
      }
      return try await beginStart(forcePull: forcePull).value
    }

    private func beginStart(forcePull: Bool) -> Task<Engine, Error> {
      let token = UUID()
      bootToken = token
      phase = .starting(progress: .kernel, operation: nil)
      log("Starting engine")
      let task = Task<Engine, Error> {
        try await self.boot(forcePull: forcePull, token: token)
      }
      startTask = task
      return task
    }

    private func boot(forcePull: Bool, token: UUID) async throws -> Engine {
      defer {
        if bootToken == token {
          startTask = nil
          bootToken = nil
        }
      }
      do {
        // CPU-bound unpack must not run on this actor. Status polls share it, so a
        // long start() would freeze the UI on the last logged phase.
        let worker = Task.detached { [forcePull] in
          try await Engine.start(forcePull: forcePull) { phase in
            Task { await self.note(phase, token: token) }
          }
        }
        let started = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        guard !Task.isCancelled, bootToken == token else {
          try? await started.stop()
          throw CancellationError()
        }
        let version = await probeVersion(baseURL: started.baseURL)
        guard !Task.isCancelled, bootToken == token else {
          try? await started.stop()
          throw CancellationError()
        }
        gotenbergVersion = version
        engine = started
        generationDigest = started.imageDigest
        phase = .running
        healthFailureStreak = 0
        log("Ready at \(started.baseURL.absoluteString)")
        if let version {
          log("Gotenberg \(version)")
        } else {
          log("Gotenberg version unavailable")
        }
        touchIdle()
        startWatchdog()
        return started
      } catch {
        guard !(error is CancellationError), bootToken == token else {
          throw error
        }
        engine = nil
        fail(error)
        throw error
      }
    }

    private func note(_ phase: EnginePhase, token: UUID) {
      guard bootToken == token else { return }
      self.phase = .starting(progress: phase, operation: nil)
      log(phase.label)
    }

    private func touchIdle() {
      idleTask?.cancel()
      idleTask = Task { [idle = EngineIdentity.idle] in
        try? await Task.sleep(for: idle)
        guard !Task.isCancelled else { return }
        await self.idleTimeout()
      }
    }

    private func idleTimeout() async {
      guard engine != nil else { return }
      log("Idle timeout")
      await stop()
    }

    private func startWatchdog() {
      watchdogTask?.cancel()
      watchdogTask = Task {
        while !Task.isCancelled {
          try? await Task.sleep(for: EngineIdentity.watchdog)
          guard !Task.isCancelled else { return }
          await self.checkHealth()
        }
      }
    }

    private func probeVersion(baseURL: URL) async -> String? {
      var lastError: String?
      for attempt in 1...EngineIdentity.versionProbeAttempts {
        guard !Task.isCancelled else { return nil }
        do {
          if let version = try await client.version(baseURL: baseURL) {
            return version
          }
          // 404 / empty — Gotenberg is up but does not expose /version.
          return nil
        } catch {
          lastError = EngineError.message(for: error)
          if attempt < EngineIdentity.versionProbeAttempts {
            try? await Task.sleep(for: EngineIdentity.versionProbeBackoff)
          }
        }
      }
      if let lastError {
        log("Version probe failed: \(lastError)")
      }
      return nil
    }

    private func checkHealth() async {
      guard let engine, startTask == nil, operationTask == nil, activeSubmits == 0,
        case .running = phase
      else { return }
      do {
        // Built-in health uses loopback only; Local Network denial does not apply.
        // Probes use a dedicated HTTP session so converts cannot starve them.
        try await client.checkHealth(baseURL: engine.baseURL)
        recoverCount = 0
        healthFailureStreak = 0
        return
      } catch {
        healthFailureStreak += 1
        log(
          "Engine unhealthy (\(healthFailureStreak)/\(EngineIdentity.healthFailureThreshold)): \(EngineError.message(for: error))"
        )
      }
      // Re-check after the probe await — a convert may have started meanwhile.
      guard activeSubmits == 0, startTask == nil, operationTask == nil, case .running = phase else {
        return
      }
      guard healthFailureStreak >= EngineIdentity.healthFailureThreshold else { return }
      await recover()
    }

    private func recover() async {
      guard activeSubmits == 0 else {
        log("Skipping recovery; convert in progress")
        return
      }
      recoverCount += 1
      healthFailureStreak = 0
      if recoverCount > EngineIdentity.recoverAttempts {
        await stop()
        phase = .failed("Engine crashed repeatedly. Start Engine to try again.")
        log("Gave up after \(EngineIdentity.recoverAttempts) recoveries")
        return
      }
      phase = .starting(progress: nil, operation: "Recovering engine")
      log("Recovering engine (\(recoverCount)/\(EngineIdentity.recoverAttempts))")
      let current = engine
      engine = nil
      gotenbergVersion = nil
      if let current {
        try? await current.stop()
      }
      do {
        _ = try await ensureEngine(forcePull: false)
      } catch {
        phase = .failed(EngineError.message(for: error))
      }
    }

    private func finishOperation() {
      operationTask = nil
    }

    private func flush(_ trace: HTTPTrace) {
      for line in trace.snapshot() {
        log(line)
      }
    }

    private func fail(_ error: Error) {
      let message = EngineError.message(for: error)
      if case .failed(let current) = phase, current == message {
        return
      }
      phase = .failed(message)
      log("Failed: \(message)")
    }

    func clearLogs() {
      logs = []
      EngineLogFile.clear()
    }

    private func log(_ message: String) {
      EngineLogEntry.append(message, to: &logs)
      fputs("\(message)\n", stdout)
      fflush(stdout)
      EngineLogFile.rotateIfNeeded()
    }

    private var failedMessage: String? {
      if case .failed(let message) = phase { return message }
      return nil
    }

    private func cachedImageDigest() -> String? {
      if let generationDigest { return generationDigest }
      let digest = EngineGeneration.load()?.imageDigest
      generationDigest = digest
      return digest
    }
  }

#endif
