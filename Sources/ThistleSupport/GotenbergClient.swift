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

  private let session: URLSession

  public init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 600
    let queue = OperationQueue()
    queue.name = "gotenberg.http"
    queue.maxConcurrentOperationCount = 1
    session = URLSession(configuration: config, delegate: nil, delegateQueue: queue)
  }

  public func ping(baseURL: URL) async -> Bool {
    do {
      let (_, response) = try await session.data(for: Self.healthRequest(baseURL: baseURL))
      return Self.healthStatus(response).ok
    } catch {
      return false
    }
  }

  public static func waitUntilHealthy(baseURL: URL, timeout: Duration = .seconds(180)) async throws
  {
    let request = healthRequest(baseURL: baseURL)
    let deadline = ContinuousClock.now + timeout
    var lastError = "timed out"
    while ContinuousClock.now < deadline {
      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = healthStatus(response)
        if status.ok { return }
        lastError = status.detail
      } catch {
        lastError = String(describing: error)
      }
      try await Task.sleep(for: .milliseconds(500))
    }
    throw EngineError.healthCheckFailed(lastError)
  }

  public func submit(
    baseURL: URL,
    path: String,
    fields: [String: String],
    files: [FileRefDTO],
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
    request.httpBody = try multipartBody(boundary: boundary, fields: fields, files: files)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      trace?.add("  -> no HTTP response")
      throw EngineError.convertFailed(status: -1, body: "no HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
      let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
      trace?.add("  -> HTTP \(http.statusCode) \(text)")
      throw EngineError.convertFailed(status: http.statusCode, body: text)
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
    fields: [String: String],
    files: [FileRefDTO],
    into trace: HTTPTrace?
  ) {
    guard let trace else { return }
    trace.add("POST \(url.absoluteString)")
    for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
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

  private func multipartBody(
    boundary: String,
    fields: [String: String],
    files: [FileRefDTO]
  ) throws -> Data {
    var body = Data()
    for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
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

  private func headerValue(_ value: String) -> String {
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
}

extension Data {
  fileprivate mutating func append(ascii string: String) {
    append(Data(string.utf8))
  }
}
