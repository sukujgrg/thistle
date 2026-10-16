import Foundation
import Testing

@testable import ThistleSupport

struct GotenbergClientTests {
  private let url = URL(string: "https://engine.example/api")!

  @Test func authenticationAppliesToHealthVersionAndConversion() async throws {
    let credentials = RemoteCredentials(
      authentication: .basic, username: "tester", secret: "pass:word")
    let client = GotenbergClient { request in
      #expect(
        request.value(forHTTPHeaderField: "Authorization") == "Basic dGVzdGVyOnBhc3M6d29yZA==")
      let url = try #require(request.url)
      #expect(url.path.hasPrefix("/api/"))
      let body = url.lastPathComponent == "version" ? "8.37.0\n" : "{}"
      return (
        Data(body.utf8),
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!
      )
    }
    try await client.checkHealth(baseURL: url, credentials: credentials)
    #expect(try await client.version(baseURL: url, credentials: credentials) == "8.37.0")
    let trace = HTTPTrace()
    _ = try await client.submit(
      baseURL: url, path: "/forms/pdfengines/stamp", fields: [], files: [],
      credentials: credentials, trace: trace)
    #expect(!trace.snapshot().joined().contains("pass:word"))
    #expect(!trace.snapshot().joined().contains("dGVzdGVy"))
  }

  @Test func bearerTokenAndPublicVersionFallback() async throws {
    let client = GotenbergClient { request in
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
      return (
        Data(),
        HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!
      )
    }
    #expect(
      try await client.version(
        baseURL: url, credentials: RemoteCredentials(authentication: .bearer, secret: "test-token"))
        == nil)
  }

  @Test(arguments: [401, 403]) func authenticationErrorsDoNotEchoSecrets(code: Int) async throws {
    let client = GotenbergClient { request in
      (
        Data("echoed test-token".utf8),
        HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: [:])!
      )
    }
    let credentials = RemoteCredentials(authentication: .bearer, secret: "test-token")
    do {
      _ = try await client.version(baseURL: url, credentials: credentials)
      Issue.record("Expected an authentication error")
    } catch {
      #expect(!EngineError.message(for: error).contains("test-token"))
      #expect(EngineError.message(for: error).contains("HTTP \(code)"))
    }
    let trace = HTTPTrace()
    do {
      _ = try await client.submit(
        baseURL: url, path: "forms/test", fields: [], files: [], credentials: credentials,
        trace: trace)
      Issue.record("Expected an authentication error")
    } catch {
      #expect(!trace.snapshot().joined().contains("test-token"))
    }
  }

  @Test func unauthenticatedRequestsHaveNoAuthorization() async throws {
    let client = GotenbergClient { request in
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      return (
        Data("8.37.0".utf8),
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      )
    }
    _ = try await client.version(baseURL: url)
  }

  @Test func secretFormFieldsRemainRedactedWithRepeatedFields() async throws {
    let client = GotenbergClient { request in
      (
        Data("{}".utf8),
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      )
    }
    let trace = HTTPTrace()
    _ = try await client.submit(
      baseURL: url, path: "forms/test",
      fields: [
        MultipartField("userPassword", "secret-one"), MultipartField("cookies", "secret-two"),
      ], files: [], trace: trace)
    #expect(!trace.snapshot().joined().contains("secret-"))
    #expect(trace.snapshot().filter { $0.contains("<redacted>") }.count == 2)
  }

  @Test func multipartPreservesParallelEmptyValuesAndUploadOrder() throws {
    let fields = [
      MultipartField("stampSource", "text"), MultipartField("stampExpression", "FIRST"),
      MultipartField("stampPages", ""), MultipartField("stampOptions", ""),
      MultipartField("stampSource", "text"), MultipartField("stampExpression", "SECOND"),
      MultipartField("stampPages", "2"), MultipartField("stampOptions", "{}"),
    ]
    let body = try GotenbergClient.multipartBody(boundary: "test", fields: fields, files: [])
    let parts = String(decoding: body, as: UTF8.self).components(separatedBy: "--test\r\n")
      .dropFirst()
    #expect(parts.count == 8)
    #expect(parts[parts.startIndex + 2].contains("name=\"stampPages\"\r\n\r\n\r\n"))
    #expect(parts[parts.startIndex + 6].contains("name=\"stampPages\"\r\n\r\n2\r\n"))
    let roundtrip = try JSONDecoder().decode(
      [MultipartField].self, from: JSONEncoder().encode(fields))
    #expect(roundtrip == fields)
  }

  @Test func redirectsCannotLeakCredentialsAcrossOrigins() {
    #expect(
      APIRedirectDelegate.allows(from: url, to: URL(string: "https://engine.example:443/redirect")))
    #expect(!APIRedirectDelegate.allows(from: url, to: URL(string: "https://other.example/api")))
    #expect(!APIRedirectDelegate.allows(from: url, to: URL(string: "http://engine.example/api")))
    #expect(
      !APIRedirectDelegate.allows(from: url, to: URL(string: "https://engine.example:8443/api")))
    #expect(
      !APIRedirectDelegate.allows(from: url, to: URL(string: "https://user@engine.example/api")))
  }
}
