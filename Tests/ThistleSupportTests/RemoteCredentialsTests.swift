import Foundation
import Testing

@testable import ThistleSupport

struct RemoteCredentialsTests {
  @Test func invalidAuthenticationIsRejected() {
    #expect(throws: EngineError.self) {
      try RemoteCredentials(authentication: .basic, username: "bad:user", secret: "password")
        .authorizationHeader()
    }
    #expect(throws: EngineError.self) {
      try RemoteCredentials(authentication: .bearer, secret: "token\r\nheader")
        .authorizationHeader()
    }
    #expect(throws: EngineError.self) {
      try RemoteCredentials(authentication: .bearer).authorizationHeader()
    }
    #expect(throws: EngineError.self) {
      try RemoteCredentials(authentication: .bearer, secret: "token\u{0}value")
        .authorizationHeader()
    }
    #expect(throws: EngineError.self) {
      try RemoteCredentials(authentication: .bearer, secret: "token\n").authorizationHeader()
    }
    #expect(throws: EngineError.self) {
      try EngineSettings.parseURL("https://name:password@engine.example")
    }
  }

  @Test func baseURLsAreNormalizedForCredentialLookup() throws {
    #expect(
      try EngineSettings.parseURL("https://ENGINE.example/api/").absoluteString
        == "https://engine.example/api")
    #expect(throws: EngineError.self) {
      try EngineSettings.parseURL("https://engine.example/api?token=secret")
    }
  }

  @Test func echoedCredentialsAreRedacted() throws {
    let credentials = RemoteCredentials(
      authentication: .basic, username: "name", secret: "password")
    let header = try #require(try credentials.authorizationHeader())
    let text = credentials.redacting("echo password and \(header)")
    #expect(!text.contains("password"))
    #expect(!text.contains(header))
  }

  @Test func basicCredentialsAreRedactedEvenWhenThePasswordMatchesTheScheme() throws {
    let credentials = RemoteCredentials(authentication: .basic, username: "name", secret: "Basic")
    let header = try #require(try credentials.authorizationHeader())
    let token = String(try #require(header.split(separator: " ").last))
    let text = credentials.redacting("\(header) and \(token)")
    #expect(!text.contains(token))
    #expect(!text.contains("Basic"))
  }

  @Test func keychainRoundTripIsScopedToTheAPIURL() throws {
    guard ProcessInfo.processInfo.environment["THISTLE_KEYCHAIN_QA"] == "1" else { return }
    let host = "https://thistle-test-\(UUID().uuidString).invalid"
    let url = URL(string: host + "/api")!
    let other = URL(string: host + "/other-api")!
    let credentials = RemoteCredentials(
      authentication: .basic, username: "test-user", secret: "test-password")
    defer { try? RemoteCredentialStore.save(RemoteCredentials(), for: url) }
    try RemoteCredentialStore.save(credentials, for: url)
    #expect(try RemoteCredentialStore.load(for: url) == credentials)
    #expect(try RemoteCredentialStore.load(for: other) == RemoteCredentials())
    try RemoteCredentialStore.save(
      RemoteCredentials(authentication: .bearer, secret: "test-token"), for: url)
    #expect(try RemoteCredentialStore.load(for: url).authentication == .bearer)
    try RemoteCredentialStore.save(RemoteCredentials(), for: url)
    #expect(try RemoteCredentialStore.load(for: url) == RemoteCredentials())
  }
}
