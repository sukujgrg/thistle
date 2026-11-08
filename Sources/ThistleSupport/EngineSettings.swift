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
  /// Default plus alternates offered when the Local API port is busy.
  public static let suggestedHostAPIPorts = [18_765, 18_766, 18_767, 28_765]

  public var mode: EngineMode
  public var remoteURL: String
  /// Host loopback TCP port for the built-in Local API (`127.0.0.1`).
  public var hostAPIPort: Int

  public init(
    mode: EngineMode = .builtIn,
    remoteURL: String = "",
    hostAPIPort: Int = EngineIdentity.hostAPIPort
  ) {
    self.mode = mode
    self.remoteURL = remoteURL
    self.hostAPIPort = Self.normalizedHostAPIPort(hostAPIPort)
  }

  public var usesRemote: Bool { mode == .remote }

  public var apiURL: URL? {
    guard usesRemote else { return nil }
    return try? Self.parseURL(remoteURL)
  }

  public var loopbackAPIURL: URL {
    EngineIdentity.loopbackAPIURL(port: hostAPIPort)
  }

  enum CodingKeys: String, CodingKey {
    case mode
    case remoteURL
    case hostAPIPort
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(EngineMode.self, forKey: .mode) ?? .builtIn
    remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL) ?? ""
    let decodedPort =
      try container.decodeIfPresent(Int.self, forKey: .hostAPIPort) ?? EngineIdentity.hostAPIPort
    hostAPIPort = Self.normalizedHostAPIPort(decodedPort)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(mode, forKey: .mode)
    try container.encode(remoteURL, forKey: .remoteURL)
    try container.encode(hostAPIPort, forKey: .hostAPIPort)
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

  /// Valid TCP port in `1...65535`; otherwise the default Local API port.
  public static func normalizedHostAPIPort(_ port: Int) -> Int {
    guard isValidHostAPIPort(port) else { return EngineIdentity.hostAPIPort }
    return port
  }

  public static func isValidHostAPIPort(_ port: Int) -> Bool {
    (1...65_535).contains(port)
  }

  public static func parseHostAPIPort(_ raw: String) throws -> Int {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let port = Int(trimmed), isValidHostAPIPort(port) else {
      throw EngineError.operationFailed(
        "Local API port must be a number from 1 to 65535.")
    }
    return port
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
      throw EngineError.invalidEngineURL("could not parse the URL")
    }
    let scheme = components.scheme?.lowercased() ?? ""
    guard scheme == "http" || scheme == "https" else {
      throw EngineError.invalidEngineURL("use http or https")
    }
    guard let host = components.host, !host.isEmpty else {
      throw EngineError.invalidEngineURL("host is missing")
    }
    guard components.user == nil, components.password == nil else {
      throw EngineError.invalidEngineURL(
        "enter credentials in the authentication controls, not in the URL")
    }
    guard components.query == nil, components.fragment == nil else {
      throw EngineError.invalidEngineURL("use an API base URL without a query or fragment")
    }
    var normalized = components
    normalized.host = host.lowercased()
    while normalized.path.hasSuffix("/") {
      normalized.path.removeLast()
    }
    guard let url = normalized.url else {
      throw EngineError.invalidEngineURL("could not parse the URL")
    }
    return url
  }
}
