#if os(macOS) && arch(arm64)

  import Darwin
  import Foundation

  import ThistleSupport

  actor EngineRuntime {
    private enum Phase: Equatable {
      case idle
      case starting(String)
      case running
      case failed(String)
    }

    private var engine: Engine?
    private var startTask: Task<Engine, Error>?
    private var bootToken: UUID?
    private var phase: Phase = .idle
    private var logs: [EngineLogEntry] = []
    private var idleTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    // Lives for the helper process, not the guest. stop() cancels the
    // watchdog, but a failed boot still has to cap engine.log.
    private var rotateTask: Task<Void, Never>?
    private var recoverCount = 0
    private var generationDigest: String?
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
        phase: phaseName,
        phaseLabel: phaseLabel,
        guestURL: engine?.baseURL.absoluteString,
        failedMessage: failedMessage,
        logs: logs,
        imageDigest: engine?.imageDigest ?? cachedImageDigest()
      )
    }

    func requestStart() {
      if engine != nil || startTask != nil { return }
      recoverCount = 0
      _ = beginStart(forcePull: false)
    }

    func requestRestart() {
      phase = .starting("Restarting engine")
      log("Restarting engine")
      Task { try? await self.restart() }
    }

    func requestRefreshImage() {
      phase = .starting("Refreshing image")
      log("Refreshing image")
      Task { try? await self.refreshImage() }
    }

    func start() async throws {
      requestStart()
      if let startTask {
        _ = try await startTask.value
      }
    }

    func stop(setIdle: Bool = true, logStop: Bool = true) async {
      if setIdle {
        phase = .starting("Stopping engine")
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
      if let current {
        try? await current.stop()
      }
      try? FileManager.default.removeItem(at: Paths.runtimeState)
      if setIdle {
        phase = .idle
      }
      if logStop {
        log("Engine stopped")
      }
    }

    func restart() async throws {
      await stop(setIdle: false, logStop: false)
      try await start()
    }

    func refreshImage() async throws {
      await stop(setIdle: false, logStop: false)
      phase = .starting("Refreshing image")
      do {
        try await Engine.pullImage()
        _ = try await ensureEngine(forcePull: false)
      } catch {
        fail(error)
        throw error
      }
    }

    func reset() async throws {
      phase = .starting("Resetting engine")
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

    func submit(jobID: String, path: String, fields: [String: String], files: [FileRefDTO])
      async throws -> JobResultDTO
    {
      let running = try await ensureEngine(forcePull: false)
      touchIdle()
      let trace = HTTPTrace()
      let result: GotenbergClient.Response
      do {
        result = try await client.submit(
          baseURL: running.baseURL, path: path, fields: fields, files: files, trace: trace)
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
      phase = .starting(EnginePhase.kernel.label)
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
        engine = started
        generationDigest = started.imageDigest
        phase = .running
        log("Ready at \(started.baseURL.absoluteString)")
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
      self.phase = .starting(phase.label)
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

    private func checkHealth() async {
      guard let engine, startTask == nil, case .running = phase else { return }
      let ok = await client.ping(baseURL: engine.baseURL)
      if ok {
        recoverCount = 0
        return
      }
      log("Engine unhealthy")
      await recover()
    }

    private func recover() async {
      recoverCount += 1
      if recoverCount > EngineIdentity.recoverAttempts {
        await stop()
        phase = .failed("Engine crashed repeatedly. Start Engine to try again.")
        log("Gave up after \(EngineIdentity.recoverAttempts) recoveries")
        return
      }
      log("Recovering engine (\(recoverCount)/\(EngineIdentity.recoverAttempts))")
      let current = engine
      engine = nil
      if let current {
        try? await current.stop()
      }
      do {
        _ = try await ensureEngine(forcePull: false)
      } catch {
        phase = .failed(EngineError.message(for: error))
      }
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

    private var phaseName: String {
      switch phase {
      case .idle: "idle"
      case .starting: "starting"
      case .running: "running"
      case .failed: "failed"
      }
    }

    private var phaseLabel: String {
      switch phase {
      case .idle: "Stopped"
      case .starting(let label): label
      case .running: "Running"
      case .failed: "Failed"
      }
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
