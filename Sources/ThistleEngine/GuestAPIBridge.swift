#if os(macOS) && arch(arm64)

  import Darwin
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
      let fd = vsock.fileDescriptor
      defer {
        // Full close only after both directions have finished (or failed).
        try? vsock.close()
      }

      // Match guest forwarder: half-close on EOF, drain the peer, never cancelAll
      // the response path when the request side finishes.
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await self.pipeTCPToVsock(connection: connection, fd: fd)
        }
        group.addTask {
          try await self.pipeVsockToTCP(fd: fd, connection: connection)
        }
        var firstError: Error?
        while let result = await group.nextResult() {
          if case .failure(let error) = result, firstError == nil {
            firstError = error
          }
        }
        if let firstError {
          throw firstError
        }
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

    /// Host TCP → guest vsock. Request EOF only shuts down vsock writes.
    private func pipeTCPToVsock(connection: NWConnection, fd: Int32) async throws {
      while !Task.isCancelled {
        let data = try await receive(from: connection)
        if data.isEmpty {
          _ = Darwin.shutdown(fd, SHUT_WR)
          return
        }
        try await writeAll(data, to: fd)
      }
    }

    /// Guest vsock → host TCP. Drain until vsock EOF, then finish the NW stream.
    private func pipeVsockToTCP(fd: Int32, connection: NWConnection) async throws {
      while !Task.isCancelled {
        let data = try await readChunk(from: fd)
        if data.isEmpty {
          try await finish(connection)
          return
        }
        try await send(data, on: connection)
      }
    }

    private func receive(from connection: NWConnection) async throws -> Data {
      while true {
        let chunk: (data: Data?, isComplete: Bool) =
          try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
              data, _, isComplete, error in
              if let error {
                continuation.resume(throwing: error)
                return
              }
              continuation.resume(returning: (data, isComplete))
            }
          }
        if let data = chunk.data, !data.isEmpty {
          return data
        }
        if chunk.isComplete {
          return Data()
        }
        // Empty incomplete receive — keep polling.
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

    private func finish(_ connection: NWConnection) async throws {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
          content: nil,
          contentContext: .defaultStream,
          isComplete: true,
          completion: .contentProcessed { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          })
      }
    }

    private func writeAll(_ data: Data, to fd: Int32) async throws {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            try data.withUnsafeBytes { raw in
              guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
              var offset = 0
              while offset < raw.count {
                let wrote = Darwin.write(fd, base + offset, raw.count - offset)
                if wrote < 0 {
                  if errno == EINTR { continue }
                  throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO)
                }
                if wrote == 0 {
                  throw EngineError.apiBridgeFailed("vsock write returned 0")
                }
                offset += wrote
              }
            }
            continuation.resume()
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }

    private func readChunk(from fd: Int32) async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          var buffer = [UInt8](repeating: 0, count: 64 * 1024)
          while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 {
              if errno == EINTR { continue }
              continuation.resume(throwing: POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO))
              return
            }
            if n == 0 {
              continuation.resume(returning: Data())
              return
            }
            continuation.resume(returning: Data(buffer.prefix(n)))
            return
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
