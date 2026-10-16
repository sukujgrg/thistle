import Foundation
import Security

public enum RemoteAuthentication: String, Codable, CaseIterable, Sendable, Identifiable {
  case none, basic, bearer
  public var id: String { rawValue }
  public var label: String {
    switch self {
    case .none: "None"
    case .basic: "Basic"
    case .bearer: "Bearer token"
    }
  }
}

public struct RemoteCredentials: Codable, Equatable, Sendable {
  public var authentication: RemoteAuthentication
  public var username: String
  public var secret: String

  public init(
    authentication: RemoteAuthentication = .none, username: String = "", secret: String = ""
  ) {
    self.authentication = authentication
    self.username = username
    self.secret = secret
  }

  public func authorizationHeader() throws -> String? {
    switch authentication {
    case .none:
      return nil
    case .basic:
      guard !username.isEmpty, !username.contains(":"), !username.contains(where: { $0.isNewline })
      else {
        throw EngineError.operationFailed(
          "Enter a Basic authentication username without colons or newlines.")
      }
      return "Basic " + Data("\(username):\(secret)".utf8).base64EncodedString()
    case .bearer:
      guard secret.range(of: #"\A[A-Za-z0-9._~+/\-]+=*\z"#, options: .regularExpression) != nil
      else {
        throw EngineError.operationFailed(
          "Enter a valid bearer token without whitespace or control characters.")
      }
      return "Bearer \(secret)"
    }
  }

  public func redacting(_ text: String) -> String {
    guard authentication != .none, !secret.isEmpty else { return text }
    var result = text
    if let header = try? authorizationHeader() {
      result = result.replacingOccurrences(of: header, with: "<redacted>")
      if let token = header.split(separator: " ", maxSplits: 1).last {
        result = result.replacingOccurrences(of: String(token), with: "<redacted>")
      }
    }
    return result.replacingOccurrences(of: secret, with: "<redacted>")
  }
}

/// Credentials are scoped to the complete API URL, including any reverse-proxy path.
public enum RemoteCredentialStore {
  private static let service = "dev.thistle.remote-api"

  private static func query(for url: URL) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: url.absoluteString,
    ]
  }

  public static func load(for url: URL) throws -> RemoteCredentials {
    var query = query(for: url)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return RemoteCredentials() }
    try check(status)
    guard let data = result as? Data else {
      throw EngineError.operationFailed(
        "The saved API credentials could not be read from Keychain.")
    }
    return try JSONDecoder().decode(RemoteCredentials.self, from: data)
  }

  public static func save(_ credentials: RemoteCredentials, for url: URL) throws {
    let query = query(for: url)
    if credentials.authentication == .none {
      let status = SecItemDelete(query as CFDictionary)
      if status != errSecItemNotFound { try check(status) }
      return
    }
    _ = try credentials.authorizationHeader()
    let data = try JSONEncoder().encode(credentials)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      try check(SecItemAdd(item as CFDictionary, nil))
    } else {
      try check(status)
    }
  }

  private static func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
      throw EngineError.operationFailed("Keychain: \(detail)")
    }
  }
}
