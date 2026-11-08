import Foundation
import Testing

@testable import ThistleSupport

struct EngineSettingsTests {
  @Test func parseURLRequiresHTTP() throws {
    #expect(throws: EngineError.self) {
      try EngineSettings.parseURL("")
    }
    #expect(throws: EngineError.self) {
      try EngineSettings.parseURL("ftp://example.com")
    }
    #expect(throws: EngineError.self) {
      try EngineSettings.parseURL("http://")
    }
  }

  @Test func parseURLAcceptsBareHostAndNormalizesSlash() throws {
    #expect(try EngineSettings.parseURL("127.0.0.1:3000").absoluteString == "http://127.0.0.1:3000")
    #expect(
      try EngineSettings.parseURL("https://gotenberg.example/").absoluteString
        == "https://gotenberg.example")
  }

  @Test func emptyURLUsesSharedHint() {
    do {
      _ = try EngineSettings.parseURL("   ")
      Issue.record("expected invalidEngineURL")
    } catch let error as EngineError {
      #expect(EngineError.message(for: error).contains(EngineSettings.urlHint))
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func messagePrefersEngineErrorDescription() {
    let error = EngineError.notRunning
    #expect(EngineError.message(for: error) == error.description)
    #expect(EngineError.message(for: CocoaError(.fileNoSuchFile)) == CocoaError(.fileNoSuchFile).localizedDescription)
  }

  @Test func hostAPIPortDefaultsAndSuggestions() {
    #expect(EngineSettings().hostAPIPort == EngineIdentity.hostAPIPort)
    #expect(EngineSettings.suggestedHostAPIPorts == [18_765, 18_766, 18_767, 28_765])
    #expect(EngineSettings().loopbackAPIURL.absoluteString == "http://127.0.0.1:18765")
    #expect(
      EngineSettings(hostAPIPort: 18_766).loopbackAPIURL.absoluteString
        == "http://127.0.0.1:18766")
  }

  @Test func hostAPIPortValidation() throws {
    #expect(EngineSettings.isValidHostAPIPort(1))
    #expect(EngineSettings.isValidHostAPIPort(65_535))
    #expect(!EngineSettings.isValidHostAPIPort(0))
    #expect(!EngineSettings.isValidHostAPIPort(65_536))
    #expect(EngineSettings.normalizedHostAPIPort(0) == EngineIdentity.hostAPIPort)
    #expect(try EngineSettings.parseHostAPIPort("18766") == 18_766)
    #expect(throws: EngineError.self) {
      try EngineSettings.parseHostAPIPort("0")
    }
    #expect(throws: EngineError.self) {
      try EngineSettings.parseHostAPIPort("abc")
    }
  }

  @Test func hostAPIPortDecodeMissingKeyUsesDefault() throws {
    let data = Data(#"{"mode":"builtIn","remoteURL":""}"#.utf8)
    let settings = try JSONDecoder().decode(EngineSettings.self, from: data)
    #expect(settings.hostAPIPort == EngineIdentity.hostAPIPort)
  }
}

struct JobResultTests {
  @Test func jsonResponseDoesNotWriteAFile() throws {
    let response = GotenbergClient.Response(
      data: Data("{}".utf8),
      mimeType: "application/json",
      suggestedExtension: "json",
      jsonPreview: "{}"
    )
    let result = try response.jobResult(jobID: "unused")
    #expect(result.jsonPreview == "{}")
    #expect(result.outputPath == nil)
    #expect(result.suggestedExtension == "json")
  }
}
