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
