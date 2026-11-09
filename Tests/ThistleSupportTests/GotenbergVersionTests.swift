import Foundation
import Testing

@testable import ThistleSupport

struct GotenbergVersionTests {
  @Test func majorNineIsRequiredWhenVersionIsKnown() {
    #expect(GotenbergRequirement.issue(version: "8.40.0")?.contains("Gotenberg 9") == true)
    #expect(GotenbergRequirement.issue(version: "v8.37.0") != nil)
    #expect(GotenbergRequirement.issue(version: "9.0.0") == nil)
    #expect(GotenbergRequirement.issue(version: "v9.2.0") == nil)
    #expect(GotenbergRequirement.issue(version: "10.0.0") == nil)
  }

  @Test func unknownCustomVersionsDoNotDisableActions() {
    #expect(GotenbergRequirement.issue(version: "custom") == nil)
    #expect(GotenbergRequirement.issue(version: nil) == nil)
  }

  @Test func olderHelperStatusWithoutVersionStillDecodes() throws {
    let dto = EngineStatusDTO(phase: "running", phaseLabel: "Running", gotenbergVersion: "9.2.0")
    let data = try JSONEncoder().encode(dto)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "gotenbergVersion")
    let older = try JSONDecoder().decode(
      EngineStatusDTO.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(older.gotenbergVersion == nil)
  }

  @Test func latestReleaseUsesUpstreamAndDoesNotSendAPIAuthentication() async throws {
    let checker = GotenbergReleaseChecker { request in
      #expect(
        request.url?.absoluteString
          == "https://api.github.com/repos/gotenberg/gotenberg/releases/latest")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      return (
        Data(#"{"tag_name":"v9.2.0","prerelease":false,"draft":false}"#.utf8),
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      )
    }
    let release = try await checker.latest()
    #expect(release.version == "9.2.0")
    #expect(
      release.url.absoluteString == "https://github.com/gotenberg/gotenberg/releases/tag/v9.2.0")
  }

  @Test func failedReleaseCheckIsAnError() async {
    let checker = GotenbergReleaseChecker { request in
      (
        Data(),
        HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: [:])!
      )
    }
    await #expect(throws: EngineError.self) { try await checker.latest() }
  }

  @Test func stagesEncodeStampAndRemediate() throws {
    let stages: [GotenbergStage] = [
      .stampText(
        PDFStamp.TextStage(
          text: "DRAFT", pages: "all", x: 72, y: 72, fontSize: 24, font: "Helvetica",
          color: "#C00000", opacity: 0.4, rotation: 30)),
      .remediate({
        var options = RemediateOptions()
        options.profiles = ["PDF/A-2b", "PDF/UA-1"]
        return options
      }()),
    ]
    let json = try GotenbergStage.encodeJSON(stages)
    #expect(json.contains(#""op":"stamp-text""#))
    #expect(json.contains(#""op":"remediate""#))
    #expect(json.contains("PDF\\/A-2b") || json.contains("PDF/A-2b"))
  }
}
