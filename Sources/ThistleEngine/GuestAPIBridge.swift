#if os(macOS) && arch(arm64)

  import Foundation
  import Network
  import Synchronization

  import ThistleSupport

  /// Host-side loopback TCP → guest vsock bridge for the built-in Gotenberg API.
  ///
  /// Listens on `127.0.0.1:<hostAPIPort>` and splices each connection to
  /// `dialVsock(EngineIdentity.apiVsockPort)`. All work is async; never call from
  /// MainActor status paths.
  @available(macOS 26.0, *)
  final class GuestAPIBridge: Sendable {
    typealias VsockDialer = @Sendable (UInt32) async throws -> FileHandle

    private struct State: Sendable {
      var listener: NWListener?
      var sessions: [UUID: Task<Void, Never>] = [:]
      var started = false
    }

    private let dialVsock: VsockDialer
    private let port: UInt16
    private let state = Mutex(State())

    var localURL: URL { EngineIdentity.loopbackAPIURL(port: Int(port)) }

    init(
      dialVsock: @escaping VsockDialer,
      port: UInt16 = UInt16(EngineIdentity.hostAPIPort)
    ) {
      self.dialVsock = dialVsock
      self.port = port
    }

    func start() async throws {
      let alreadyStarted = state.withLock { $0.started }
      if alreadyStarted { return }

      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = false
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host("127.0.0.1"),
        port: NWEndpoint.Port(rawValue: port)!
      )

      // Port comes only from requiredLocalEndpoint — do not also pass `on:`.
      let listener: NWListener
      do {
        listener = try NWListener(using: parameters)
      } catch {
        throw EngineError.hostAPIPortInUse(Int(port))
      }

      do {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
          let gate = StartGate(continuation)
          listener.stateUpdateHandler = { [port] state in
            switch state {
            case .ready:
              gate.resumeSuccess()
            case .failed(let error):
              let message = error.localizedDescription.lowercased()
              if message.contains("address already in use") || message.contains("in use") {
                gate.resumeFailure(EngineError.hostAPIPortInUse(Int(port)))
              } else {
                gate.resumeFailure(EngineError.apiBridgeFailed(error.localizedDescription))
              }
            case .cancelled:
              gate.resumeFailure(EngineError.apiBridgeFailed("listener cancelled"))
            default:
              break
            }
          }
          listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
          }
          self.state.withLock {
            $0.listener = listener
            $0.started = true
          }
          listener.start(queue: DispatchQueue(label: "dev.thistle.api-bridge", qos: .userInitiated))
        }
      } catch {
        stop()
        throw error
      }
    }

    func stop() {
      let (listener, sessions): (NWListener?, [UUID: Task<Void, Never>]) = state.withLock {
        let listener = $0.listener
        let sessions = $0.sessions
        $0.listener = nil
        $0.sessions = [:]
        $0.started = false
        return (listener, sessions)
      }
      listener?.cancel()
      for (_, task) in sessions {
        task.cancel()
      }
    }

    private func serve(_ connection: NWConnection) {
      let id = UUID()
      let task = Task.detached(priority: .userInitiated) { [weak self] in
        guard let self else {
          connection.cancel()
          return
        }
        defer {
          self.state.withLock { $0.sessions[id] = nil }
          connection.cancel()
        }
        do {
          try await self.splice(connection: connection)
        } catch {
          // Connection-level failures are expected when clients disconnect.
        }
      }
      state.withLock { $0.sessions[id] = task }
    }

    private func splice(connection: NWConnection) async throws {
      connection.start(queue: DispatchQueue(label: "dev.thistle.api-bridge.conn", qos: .userInitiated))
      try await waitReady(connection)

      let vsock = try await dialVsock(EngineIdentity.apiVsockPort)
      defer {
        try? vsock.close()
      }

      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await self.pipe(from: connection, to: vsock)
        }
        group.addTask {
          try await self.pipe(from: vsock, to: connection)
        }
        _ = try await group.next()
        group.cancelAll()
      }
    }

    private func waitReady(_ connection: NWConnection) async throws {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let gate = StartGate(continuation)
        connection.stateUpdateHandler = { state in
          switch state {
          case .ready:
            gate.resumeSuccess()
          case .failed(let error):
            gate.resumeFailure(error)
          case .cancelled:
            gate.resumeFailure(CancellationError())
          default:
            break
          }
        }
      }
    }

    private func pipe(from connection: NWConnection, to handle: FileHandle) async throws {
      while !Task.isCancelled {
        let data = try await receive(from: connection)
        if data.isEmpty {
          try handle.close()
          return
        }
        try handle.write(contentsOf: data)
      }
    }

    private func pipe(from handle: FileHandle, to connection: NWConnection) async throws {
      while !Task.isCancelled {
        let data = try await read(from: handle)
        if data.isEmpty {
          connection.send(
            content: nil, contentContext: .defaultStream, isComplete: true,
            completion: .contentProcessed({ _ in }))
          return
        }
        try await send(data, on: connection)
      }
    }

    private func receive(from connection: NWConnection) async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
          data, _, isComplete, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }
          if let data, !data.isEmpty {
            continuation.resume(returning: data)
            return
          }
          continuation.resume(returning: Data())
        }
      }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
          content: data,
          contentContext: .defaultMessage,
          isComplete: false,
          completion: .contentProcessed { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          })
      }
    }

    private func read(from handle: FileHandle) async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            if let data = try handle.read(upToCount: 64 * 1024) {
              continuation.resume(returning: data)
            } else {
              continuation.resume(returning: Data())
            }
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }
  }

  private final class StartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    init(_ continuation: CheckedContinuation<Void, Error>) {
      self.continuation = continuation
    }

    func resumeSuccess() {
      lock.lock()
      defer { lock.unlock() }
      guard !finished else { return }
      finished = true
      continuation?.resume()
      continuation = nil
    }

    func resumeFailure(_ error: Error) {
      lock.lock()
      defer { lock.unlock() }
      guard !finished else { return }
      finished = true
      continuation?.resume(throwing: error)
      continuation = nil
    }
  }

#endif
