import Foundation

public final class HTTPTrace: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []

  public init() {}

  public func add(_ line: String) {
    lock.lock()
    lines.append(line)
    lock.unlock()
  }

  public func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return lines
  }
}

public actor GotenbergClient {
  public struct Response: Sendable {
    public let data: Data
    public let mimeType: String
    public let suggestedExtension: String
    public let jsonPreview: String?

    public nonisolated init(
      data: Data, mimeType: String, suggestedExtension: String, jsonPreview: String?
    ) {
      self.data = data
      self.mimeType = mimeType
      self.suggestedExtension = suggestedExtension
      self.jsonPreview = jsonPreview
    }

    public var isJSON: Bool { jsonPreview != nil }

    public nonisolated func jobResult(jobID: String) throws -> JobResultDTO {
      if isJSON {
        return JobResultDTO(jsonPreview: jsonPreview, suggestedExtension: suggestedExtension)
      }
      let output = Paths.jobDirectory(jobID).appendingPathComponent("output.\(suggestedExtension)")
      try data.write(to: output, options: .atomic)
      return JobResultDTO(
        outputPath: output.path(percentEncoded: false),
        suggestedExtension: suggestedExtension)
    }
  }

  private static let secretFields: Set<String> = [
    "cookies", "extraHttpHeaders", "password", "userPassword", "ownerPassword",
  ]

  private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  public init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 600
    config.urlCredentialStorage = nil
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    let queue = OperationQueue()
    queue.name = "gotenberg.http"
    queue.maxConcurrentOperationCount = 1
    let session = URLSession(
      configuration: config, delegate: APIRedirectDelegate(), delegateQueue: queue)
    dataLoader = { try await session.data(for: $0) }
  }

  init(dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
    self.dataLoader = dataLoader
  }

  public func checkHealth(baseURL: URL, credentials: RemoteCredentials = RemoteCredentials())
    async throws
  {
    var request = Self.healthRequest(baseURL: baseURL)
    request.setValue(try credentials.authorizationHeader(), forHTTPHeaderField: "Authorization")
    let (data, response) = try await load(request)
    try Self.checkResponse(response, data: data, credentials: credentials)
  }

  public func ping(baseURL: URL) async -> Bool {
    do {
      try await checkHealth(baseURL: baseURL)
      return true
    } catch {
      return false
    }
  }

  public func version(baseURL: URL, credentials: RemoteCredentials = RemoteCredentials())
    async throws -> String?
  {
    var request = URLRequest(url: baseURL.appending(path: "version"))
    request.timeoutInterval = 3
    request.setValue(try credentials.authorizationHeader(), forHTTPHeaderField: "Authorization")
    let (data, response) = try await load(request)
    if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
    try Self.checkResponse(response, data: data, credentials: credentials)
    guard data.count <= 256, let raw = String(data: data, encoding: .utf8) else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty || value.contains(where: { $0.isWhitespace }) || value.contains("<")
      ? nil : credentials.redacting(value)
  }

  public static func waitUntilHealthy(baseURL: URL, timeout: Duration = .seconds(180)) async throws
  {
    try await waitUntilHealthy(baseURL: baseURL, timeout: timeout) {
      try await URLSession.shared.data(for: $0)
    }
  }

  static func waitUntilHealthy(
    baseURL: URL, timeout: Duration,
    dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  ) async throws {
    let request = healthRequest(baseURL: baseURL)
    let deadline = ContinuousClock.now + timeout
    var lastError = "timed out"
    while ContinuousClock.now < deadline {
      do {
        let (_, response) = try await dataLoader(request)
        let status = healthStatus(response)
        if status.ok { return }
        lastError = status.detail
      } catch {
        try Task.checkCancellation()
        if NetworkFailure.isLocalNetworkDenied(error) { throw EngineError.localNetworkAccessDenied }
        lastError = error.localizedDescription
      }
      try await Task.sleep(for: .milliseconds(500))
    }
    throw EngineError.healthCheckFailed(lastError)
  }

  public func submit(
    baseURL: URL,
    path: String,
    fields: [MultipartField],
    files: [FileRefDTO],
    credentials: RemoteCredentials = RemoteCredentials(),
    trace: HTTPTrace? = nil
  ) async throws -> Response {
    let boundary = "Boundary-\(UUID().uuidString)"
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let url = baseURL.appending(path: trimmed)
    Self.recordRequest(url: url, fields: fields, files: files, into: trace)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 300
    request.setValue(try credentials.authorizationHeader(), forHTTPHeaderField: "Authorization")
    request.httpBody = try Self.multipartBody(boundary: boundary, fields: fields, files: files)

    let (data, response) = try await load(request)
    guard let http = response as? HTTPURLResponse else {
      trace?.add("  -> no HTTP response")
      throw EngineError.convertFailed(status: -1, body: "no HTTP response")
    }
    do {
      try Self.checkResponse(response, data: data, credentials: credentials)
    } catch {
      trace?.add("  -> \(EngineError.message(for: error))")
      throw error
    }

    let mime = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
    let ext = OutputFile.suggestedExtension(mime: mime, data: data)
    trace?.add("  -> HTTP \(http.statusCode) \(mime) \(data.count) bytes")
    return Response(
      data: data,
      mimeType: mime,
      suggestedExtension: ext,
      jsonPreview: prettyJSON(data: data, mime: mime)
    )
  }

  private static func recordRequest(
    url: URL,
    fields: [MultipartField],
    files: [FileRefDTO],
    into trace: HTTPTrace?
  ) {
    guard let trace else { return }
    trace.add("POST \(url.absoluteString)")
    for field in fields {
      let (name, value) = (field.name, field.value)
      if secretFields.contains(name) {
        trace.add("  \(name)=<redacted>")
      } else {
        trace.add("  \(name)=\(value)")
      }
    }
    for file in files {
      let size = (try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      trace.add("  \(file.field)=\(file.multipartFilename) \(size) bytes")
    }
  }

  private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await dataLoader(request)
    } catch {
      throw NetworkFailure.normalized(error)
    }
  }

  static func multipartBody(
    boundary: String,
    fields: [MultipartField],
    files: [FileRefDTO]
  ) throws -> Data {
    var body = Data()
    for field in fields {
      let (name, value) = (field.name, field.value)
      body.append(ascii: "--\(boundary)\r\n")
      body.append(ascii: "Content-Disposition: form-data; name=\"\(headerValue(name))\"\r\n\r\n")
      body.append(ascii: value)
      body.append(ascii: "\r\n")
    }
    for file in files {
      let filename = headerValue(file.multipartFilename)
      let fileData = try Data(contentsOf: file.fileURL)
      body.append(ascii: "--\(boundary)\r\n")
      body.append(
        ascii:
          "Content-Disposition: form-data; name=\"\(headerValue(file.field))\"; filename=\"\(filename)\"\r\n"
      )
      body.append(ascii: "Content-Type: application/octet-stream\r\n\r\n")
      body.append(fileData)
      body.append(ascii: "\r\n")
    }
    body.append(ascii: "--\(boundary)--\r\n")
    return body
  }

  private static func headerValue(_ value: String) -> String {
    value.map { character in
      switch character {
      case "\"", "\\", "\r", "\n": "_"
      default: character
      }
    }.reduce(into: "") { $0.append($1) }
  }

  private func prettyJSON(data: Data, mime: String) -> String? {
    let type = mime.lowercased()
    guard type.contains("json") || OutputFile.isJSON(data) else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
      return String(data: data, encoding: .utf8)
    }
    guard
      let pretty = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
      let text = String(data: pretty, encoding: .utf8)
    else {
      return String(data: data, encoding: .utf8)
    }
    return text
  }

  private static func healthRequest(baseURL: URL) -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: "health"))
    request.timeoutInterval = 2
    return request
  }

  private static func healthStatus(_ response: URLResponse) -> (ok: Bool, detail: String) {
    guard let http = response as? HTTPURLResponse else {
      return (false, "no HTTP response")
    }
    if (200..<300).contains(http.statusCode) {
      return (true, "")
    }
    return (false, "HTTP \(http.statusCode)")
  }

  private static func checkResponse(
    _ response: URLResponse, data: Data, credentials: RemoteCredentials
  ) throws {
    guard let http = response as? HTTPURLResponse else {
      throw EngineError.convertFailed(status: -1, body: "no HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
      let message: String
      if http.statusCode == 401 {
        message =
          "Authentication failed. Check the username/password or bearer token, then Connect again."
      } else if http.statusCode == 403 {
        message =
          "Access denied by the Gotenberg server. Check your credentials and server permissions."
      } else if (300..<400).contains(http.statusCode) {
        message = "The API redirected to another server. Use its final URL and connect again."
      } else {
        message = credentials.redacting(
          String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>")
      }
      throw EngineError.convertFailed(status: http.statusCode, body: message)
    }
  }
}

/// API credentials and uploaded files must never follow a redirect to another origin.
final class APIRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  static func allows(from source: URL?, to destination: URL?) -> Bool {
    guard let source, let destination else { return false }
    func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
    return source.scheme?.lowercased() == destination.scheme?.lowercased()
      && source.host?.lowercased() == destination.host?.lowercased()
      && port(source) == port(destination)
      && destination.user == nil && destination.password == nil
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard Self.allows(from: task.originalRequest?.url, to: request.url) else {
      completionHandler(nil)
      return
    }
    var next = request
    next.setValue(
      task.originalRequest?.value(forHTTPHeaderField: "Authorization"),
      forHTTPHeaderField: "Authorization")
    completionHandler(next)
  }
}

extension Data {
  fileprivate mutating func append(ascii string: String) {
    append(Data(string.utf8))
  }
}
