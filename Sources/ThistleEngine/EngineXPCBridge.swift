#if os(macOS) && arch(arm64)

  import Darwin
  import Foundation

  import ThistleSupport

  final class EngineListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let runtime: EngineRuntime
    private var bridges: [EngineXPCBridge] = []

    init(runtime: EngineRuntime) {
      self.runtime = runtime
    }

    func listener(
      _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
      guard newConnection.effectiveUserIdentifier == getuid() else {
        return false
      }
      let bridge = EngineXPCBridge(runtime: runtime)
      newConnection.exportedInterface = NSXPCInterface(with: EngineXPCProtocol.self)
      newConnection.exportedObject = bridge
      newConnection.invalidationHandler = { [weak self, weak bridge] in
        guard let self, let bridge else { return }
        self.bridges.removeAll { $0 === bridge }
      }
      bridges.append(bridge)
      newConnection.resume()
      return true
    }
  }

  final class EngineXPCBridge: NSObject, EngineXPCProtocol, @unchecked Sendable {
    private let runtime: EngineRuntime

    init(runtime: EngineRuntime) {
      self.runtime = runtime
    }

    func fetchStatus(reply: @escaping @Sendable (Data?, String?) -> Void) {
      Task {
        let dto = await runtime.status()
        do {
          reply(try JSONEncoder().encode(dto), nil)
        } catch {
          reply(nil, EngineError.message(for: error))
        }
      }
    }

    func startEngine(reply: @escaping @Sendable (String?) -> Void) {
      Task {
        await runtime.requestStart()
        reply(nil)
      }
    }

    func stopEngine(reply: @escaping @Sendable (String?) -> Void) {
      Task {
        await runtime.stop()
        reply(nil)
      }
    }

    func restartEngine(reply: @escaping @Sendable (String?) -> Void) {
      Task {
        await runtime.requestRestart()
        reply(nil)
      }
    }

    func refreshImage(reply: @escaping @Sendable (String?) -> Void) {
      Task {
        await runtime.requestRefreshImage()
        reply(nil)
      }
    }

    func resetEngine(reply: @escaping @Sendable (String?) -> Void) {
      Task { reply(await run { try await runtime.reset() }) }
    }

    func clearLogs(reply: @escaping @Sendable (String?) -> Void) {
      Task {
        await runtime.clearLogs()
        reply(nil)
      }
    }

    func submitJob(
      jobID: String, path: String, fieldsJSON: Data, filesJSON: Data,
      reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
      Task {
        do {
          let fields = try JSONDecoder().decode([String: String].self, from: fieldsJSON)
          let files = try JSONDecoder().decode([FileRefDTO].self, from: filesJSON)
          let result = try await runtime.submit(
            jobID: jobID, path: path, fields: fields, files: files)
          reply(try JSONEncoder().encode(result), nil)
        } catch {
          reply(nil, EngineError.message(for: error))
        }
      }
    }

    private func run(_ body: () async throws -> Void) async -> String? {
      do {
        try await body()
        return nil
      } catch {
        return EngineError.message(for: error)
      }
    }
  }

#endif
