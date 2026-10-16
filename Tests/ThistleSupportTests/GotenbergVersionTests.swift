import Foundation
import Testing

@testable import ThistleSupport

struct GotenbergVersionTests {
  @Test func multipleMarksRequire836ButSingleMarkRemainsCompatible() {
    let one = PDFMark(text: "DRAFT").fields(prefix: "watermark")
    #expect(
      GotenbergCompatibility.issue(
        version: "8.35.0", path: "/forms/pdfengines/watermark", fields: one) == nil)
    #expect(
      GotenbergCompatibility.issue(
        version: "8.35.0", path: "/forms/pdfengines/watermark", fields: one + one)?.contains(
          "8.36.0") == true)
    #expect(
      GotenbergCompatibility.issue(
        version: "v8.36.0-live-demo-snapshot", path: "/forms/pdfengines/watermark",
        fields: one + one) == nil)
  }

  @Test func routesAndNewOptionsHaveVersionChecks() {
    #expect(
      GotenbergCompatibility.issue(
        version: "8.35.0", path: "/forms/pdfengines/optimize", fields: []) != nil)
    #expect(
      GotenbergCompatibility.issue(
        version: "8.32.0", path: "/forms/chromium/screenshot/url",
        fields: [MultipartField("deviceScaleFactor", "2")]) != nil)
    #expect(
      GotenbergCompatibility.issue(
        version: "8.37.0", path: "/forms/pdfengines/optimize", fields: []) == nil)
  }

  @Test func unknownCustomVersionsDoNotDisableActions() {
    #expect(
      GotenbergCompatibility.issue(
        version: "custom", path: "/forms/pdfengines/optimize", fields: []) == nil)
    #expect(
      GotenbergCompatibility.issue(version: nil, path: "/forms/pdfengines/optimize", fields: [])
        == nil)
  }

  @Test func olderHelperStatusWithoutVersionStillDecodes() throws {
    let dto = EngineStatusDTO(phase: "running", phaseLabel: "Running", gotenbergVersion: "8.37.0")
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
        Data(#"{"tag_name":"v8.37.0","prerelease":false,"draft":false}"#.utf8),
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      )
    }
    let release = try await checker.latest()
    #expect(release.version == "8.37.0")
    #expect(
      release.url.absoluteString == "https://github.com/gotenberg/gotenberg/releases/tag/v8.37.0")
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
}
