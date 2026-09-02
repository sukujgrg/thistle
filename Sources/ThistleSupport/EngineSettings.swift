import Foundation

public enum EngineMode: String, Codable, Sendable, CaseIterable, Identifiable {
  case builtIn
  case remote

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .builtIn: "Built-in VM"
    case .remote: "Custom URL"
    }
  }
}

public struct EngineSettings: Codable, Equatable, Sendable {
  public static let urlHint = "enter an http(s) URL, for example http://127.0.0.1:3000"

  public var mode: EngineMode
  public var remoteURL: String

  public init(mode: EngineMode = .builtIn, remoteURL: String = "") {
    self.mode = mode
    self.remoteURL = remoteURL
  }

  public var usesRemote: Bool { mode == .remote }

  public var apiURL: URL? {
    guard usesRemote else { return nil }
    return try? Self.parseURL(remoteURL)
  }

  public static func load() -> EngineSettings {
    guard let data = try? Data(contentsOf: Paths.settings),
      let settings = try? JSONDecoder().decode(EngineSettings.self, from: data)
    else {
      return EngineSettings()
    }
    return settings
  }

  public func save() throws {
    try Paths.ensureDirectories()
    try JSONEncoder().encode(self).write(to: Paths.settings, options: .atomic)
  }

  public static func parseURL(_ raw: String) throws -> URL {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw EngineError.invalidEngineURL(urlHint)
    }
    var text = trimmed
    if !text.contains("://") {
      text = "http://\(text)"
    }
    guard let components = URLComponents(string: text) else {
      throw EngineError.invalidEngineURL("could not parse \(trimmed)")
    }
    let scheme = components.scheme?.lowercased() ?? ""
    guard scheme == "http" || scheme == "https" else {
      throw EngineError.invalidEngineURL("use http or https")
    }
    guard let host = components.host, !host.isEmpty else {
      throw EngineError.invalidEngineURL("host is missing")
    }
    var normalized = components
    if normalized.path == "/" {
      normalized.path = ""
    }
    guard let url = normalized.url else {
      throw EngineError.invalidEngineURL("could not parse \(trimmed)")
    }
    return url
  }
}
