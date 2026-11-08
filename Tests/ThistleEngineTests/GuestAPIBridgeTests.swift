#if os(macOS) && arch(arm64)

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
