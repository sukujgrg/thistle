#if os(macOS) && arch(arm64)

  import Darwin
  import Foundation
  import Network
  import Testing
  import ThistleSupport

  @testable import ThistleEngine

  struct GuestAPIBridgeTests {
    @Test func startFailsWhenPortIsBusy() async throws {
      let occupied = try await Self.listenOnEphemeralPort()
      defer { occupied.listener.cancel() }

      let bridge = GuestAPIBridge(
        dialVsock: { _ in throw EngineError.apiBridgeFailed("unused") },
        port: occupied.number
      )
      do {
        try await bridge.start()
        bridge.stop()
        Issue.record("expected hostAPIPortInUse")
      } catch let error as EngineError {
        guard case .hostAPIPortInUse(let used) = error else {
          Issue.record("unexpected \(error)")
          return
        }
        #expect(used == Int(occupied.number))
      }
    }

    @Test func stopReleasesPortForRestart() async throws {
      let port = try await Self.claimEphemeralPort()
      let first = GuestAPIBridge(
        dialVsock: { _ in throw EngineError.apiBridgeFailed("unused") },
        port: port
      )
      try await first.start()
      first.stop()
      try await Task.sleep(for: .milliseconds(100))

      let second = GuestAPIBridge(
        dialVsock: { _ in throw EngineError.apiBridgeFailed("unused") },
        port: port
      )
      try await second.start()
      second.stop()
    }

    @Test func loopbackURLContractMatchesIdentity() {
      let bridge = GuestAPIBridge(
        dialVsock: { _ in throw EngineError.apiBridgeFailed("unused") }
      )
      #expect(bridge.localURL == EngineIdentity.loopbackAPIURL)
      #expect(bridge.localURL.absoluteString == "http://127.0.0.1:18765")
    }

    @Test func spliceServesRepeatedHealthAndVersionRequests() async throws {
      let backend = try await HTTPFixture.start()
      defer { backend.stop() }

      let bridgePort = try await Self.claimEphemeralPort()
      let bridge = GuestAPIBridge(
        dialVsock: { _ in try Self.connectFileHandle(to: backend.port) },
        port: bridgePort
      )
      try await bridge.start()
      defer { bridge.stop() }

      let base = EngineIdentity.loopbackAPIURL(port: Int(bridgePort))
      let client = GotenbergClient()

      try await client.checkHealth(baseURL: base)
      #expect(try await client.version(baseURL: base) == "9.2.0")
      // Second connection must also complete — regression for first-works/later-fails.
      try await client.checkHealth(baseURL: base)
      #expect(try await client.version(baseURL: base) == "9.2.0")
    }

    private struct BoundPort {
      let number: UInt16
      let listener: NWListener
    }

    private static func listenOnEphemeralPort() async throws -> BoundPort {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
        host: "127.0.0.1",
        port: 0
      )
      let listener = try NWListener(using: parameters)
      try await waitReady(listener)
      guard let port = listener.port?.rawValue else {
        listener.cancel()
        throw EngineError.apiBridgeFailed("missing listener port")
      }
      return BoundPort(number: port, listener: listener)
    }

    private static func claimEphemeralPort() async throws -> UInt16 {
      let bound = try await listenOnEphemeralPort()
      let number = bound.number
      bound.listener.cancel()
      try await Task.sleep(for: .milliseconds(100))
      return number
    }

    private static func waitReady(_ listener: NWListener) async throws {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let gate = ResumeOnce(continuation)
        listener.newConnectionHandler = { $0.cancel() }
        listener.stateUpdateHandler = { state in
          switch state {
          case .ready: gate.success()
          case .failed(let error): gate.failure(error)
          case .cancelled: gate.failure(CancellationError())
          default: break
          }
        }
        listener.start(queue: .global(qos: .userInitiated))
      }
    }

    private static func connectFileHandle(to port: UInt16) throws -> FileHandle {
      let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
      guard fd >= 0 else {
        throw EngineError.apiBridgeFailed("socket failed")
      }
      var addr = sockaddr_in()
      addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      addr.sin_family = sa_family_t(AF_INET)
      addr.sin_port = in_port_t(port.bigEndian)
      addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
      let connected = withUnsafePointer(to: &addr) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      guard connected == 0 else {
        Darwin.close(fd)
        throw EngineError.apiBridgeFailed("connect failed errno=\(errno)")
      }
      return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
  }

  /// Minimal HTTP backend used as the dialVsock stand-in for splice tests.
  private final class HTTPFixture: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener

    private init(port: UInt16, listener: NWListener) {
      self.port = port
      self.listener = listener
    }

    static func start() async throws -> HTTPFixture {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)
      let listener = try NWListener(using: parameters)
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let gate = ResumeOnce(continuation)
        listener.newConnectionHandler = { connection in
          Self.serve(connection)
        }
        listener.stateUpdateHandler = { state in
          switch state {
          case .ready: gate.success()
          case .failed(let error): gate.failure(error)
          case .cancelled: gate.failure(CancellationError())
          default: break
          }
        }
        listener.start(queue: .global(qos: .userInitiated))
      }
      guard let port = listener.port?.rawValue else {
        listener.cancel()
        throw EngineError.apiBridgeFailed("missing fixture port")
      }
      return HTTPFixture(port: port, listener: listener)
    }

    func stop() {
      listener.cancel()
    }

    private static func serve(_ connection: NWConnection) {
      connection.start(queue: .global(qos: .userInitiated))
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
        data, _, _, error in
        if error != nil {
          connection.cancel()
          return
        }
        let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
        let body: String
        let contentType: String
        if request.contains(" /version") {
          body = "9.2.0\n"
          contentType = "text/plain"
        } else {
          body = "{}"
          contentType = "application/json"
        }
        let response = Data(
          """
          HTTP/1.1 200 OK\r
          Content-Type: \(contentType)\r
          Content-Length: \(body.utf8.count)\r
          Connection: close\r
          \r
          \(body)
          """.utf8)
        connection.send(
          content: response, contentContext: .defaultStream, isComplete: true,
          completion: .contentProcessed { _ in
            connection.cancel()
          })
      }
    }
  }

  private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
      self.continuation = continuation
    }

    func success() {
      lock.lock()
      defer { lock.unlock() }
      continuation?.resume()
      continuation = nil
    }

    func failure(_ error: Error) {
      lock.lock()
      defer { lock.unlock() }
      continuation?.resume(throwing: error)
      continuation = nil
    }
  }

#endif
