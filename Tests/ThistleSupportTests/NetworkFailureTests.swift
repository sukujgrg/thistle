import Foundation
import Testing

@testable import ThistleSupport

struct NetworkFailureTests {
  private let url = URL(string: "http://192.168.64.2:3000")!

  private func denied() -> NSError {
    NSError(
      domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue,
      userInfo: [
        NSUnderlyingErrorKey: NSError(
          domain: "kCFErrorDomainCFNetwork", code: -1009,
          userInfo: [
            "_NSURLErrorNWPathKey":
              "unsatisfied (Local network prohibited), interface: bridge101, ipv4"
          ])
      ])
  }

  @Test func reportsTheLocalNetworkPolicyInsteadOfOffline() {
    #expect(NetworkFailure.isLocalNetworkDenied(denied()))
    #expect(EngineError.message(for: denied()) == EngineError.localNetworkAccessDenied.description)
    #expect(EngineError.message(for: denied()).contains("Privacy & Security > Local Network"))
  }

  @Test func ordinaryOfflineAndConnectionFailuresAreNotPermissionErrors() {
    #expect(!NetworkFailure.isLocalNetworkDenied(URLError(.notConnectedToInternet)))
    #expect(!NetworkFailure.isLocalNetworkDenied(URLError(.cannotConnectToHost)))
    let error = NSError(
      domain: NSURLErrorDomain, code: -1009,
      userInfo: ["_NSURLErrorNWPathKey": "unsatisfied (No network route)"])
    #expect(!NetworkFailure.isLocalNetworkDenied(error))
  }

  @Test func readinessStopsOnTheFirstPermissionFailure() async {
    let attempts = RequestAttempts()
    do {
      try await GotenbergClient.waitUntilHealthy(baseURL: url, timeout: .seconds(180)) { _ in
        await attempts.increment()
        throw denied()
      }
      Issue.record("Expected a local-network permission error")
    } catch let error as EngineError {
      if case .localNetworkAccessDenied = error {
      } else {
        Issue.record("Unexpected error \(error)")
      }
    } catch { Issue.record("Unexpected error \(error)") }
    #expect(await attempts.count == 1)
  }

  @Test func readinessStillRetriesWhileTheServerIsStarting() async throws {
    let attempts = RequestAttempts()
    try await GotenbergClient.waitUntilHealthy(baseURL: url, timeout: .seconds(3)) { request in
      let count = await attempts.increment()
      if count == 1 { throw URLError(.cannotConnectToHost) }
      return (
        Data(),
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      )
    }
    #expect(await attempts.count == 2)
  }

  @Test func authenticatedRemoteRequestsAlsoReportPermissionDenial() async {
    let client = GotenbergClient { _ in throw denied() }
    do {
      try await client.checkHealth(
        baseURL: url, credentials: RemoteCredentials(authentication: .bearer, secret: "test-token"))
      Issue.record("Expected a permission error")
    } catch {
      #expect(EngineError.message(for: error) == EngineError.localNetworkAccessDenied.description)
    }
  }
}

private actor RequestAttempts {
  var count = 0
  @discardableResult func increment() -> Int {
    count += 1
    return count
  }
}
