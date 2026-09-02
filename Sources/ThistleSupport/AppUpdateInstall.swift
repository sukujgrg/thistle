import Darwin
import Foundation
import Security

public protocol AppUpdateCodeSigning: Sendable {
  func evaluate(at appURL: URL, requirement: String) throws
}

public enum AppUpdateCodeRequirement {
  public static func developerID(
    bundleIdentifier: String,
    teamID: String = EngineIdentity.developerTeamID
  ) -> String {
    let identifier = escape(bundleIdentifier)
    let team = escape(teamID)
    return
      "identifier \"\(identifier)\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \"\(team)\""
  }

  private static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}

public struct AppUpdateSecCodeSigning: AppUpdateCodeSigning {
  public init() {}

  public func evaluate(at appURL: URL, requirement: String) throws {
    var staticCode: SecStaticCode?
    let pathStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
    guard pathStatus == errSecSuccess, let staticCode else {
      throw AppUpdateValidationError.signatureInvalid
    }

    var requirementRef: SecRequirement?
    let requirementStatus = SecRequirementCreateWithString(
      requirement as CFString, [], &requirementRef)
    guard requirementStatus == errSecSuccess, let requirementRef else {
      throw AppUpdateValidationError.signatureInvalid
    }

    let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate)
    let validity = SecStaticCodeCheckValidity(staticCode, flags, requirementRef)
    guard validity == errSecSuccess else {
      throw AppUpdateValidationError.signatureInvalid
    }
  }
}

public enum AppUpdateBundleValidator {
  public static func bundleIdentifier(at appURL: URL) throws -> String? {
    let infoURL =
      appURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Info.plist")
    let infoData = try Data(contentsOf: infoURL)
    let plist = try PropertyListSerialization.propertyList(
      from: infoData,
      options: [],
      format: nil
    )
    return (plist as? [String: Any])?["CFBundleIdentifier"] as? String
  }

  public static func validate(
    at appURL: URL,
    bundleIdentifier: String,
    teamID: String = EngineIdentity.developerTeamID,
    codeSigning: any AppUpdateCodeSigning = AppUpdateSecCodeSigning()
  ) throws {
    let actualBundleIdentifier = try Self.bundleIdentifier(at: appURL)
    guard actualBundleIdentifier == bundleIdentifier else {
      throw AppUpdateValidationError.bundleIdentifierMismatch(
        expected: bundleIdentifier,
        actual: actualBundleIdentifier
      )
    }

    try codeSigning.evaluate(
      at: appURL,
      requirement: AppUpdateCodeRequirement.developerID(
        bundleIdentifier: bundleIdentifier,
        teamID: teamID
      )
    )
  }
}

public enum AppUpdateValidationError: Error, LocalizedError, Equatable, Sendable {
  case bundleIdentifierMismatch(expected: String, actual: String?)
  case signatureInvalid

  public var errorDescription: String? {
    switch self {
    case .bundleIdentifierMismatch(let expected, let actual):
      "The update bundle identifier (\(actual ?? "none")) does not match \(expected)."
    case .signatureInvalid:
      "The update is not signed with this project's Developer ID."
    }
  }
}

public struct AppUpdateReplacement: Sendable {
  public let targetURL: URL
  public let backupURL: URL

  public init(targetURL: URL, backupURL: URL) {
    self.targetURL = targetURL
    self.backupURL = backupURL
  }

  public static func perform(
    targetURL: URL,
    newAppURL: URL,
    fileManager: FileManager = .default
  ) throws -> AppUpdateReplacement {
    let backupURL =
      targetURL
      .deletingLastPathComponent()
      .appendingPathComponent(".\(targetURL.lastPathComponent).backup-\(UUID().uuidString)")

    try fileManager.moveItem(at: targetURL, to: backupURL)
    do {
      try fileManager.moveItem(at: newAppURL, to: targetURL)
    } catch {
      try? fileManager.moveItem(at: backupURL, to: targetURL)
      throw error
    }
    return AppUpdateReplacement(targetURL: targetURL, backupURL: backupURL)
  }

  public func restore(fileManager: FileManager = .default) throws {
    if fileManager.fileExists(atPath: targetURL.path) {
      try fileManager.removeItem(at: targetURL)
    }
    try fileManager.moveItem(at: backupURL, to: targetURL)
  }

  public func discardBackup(fileManager: FileManager = .default) {
    try? fileManager.removeItem(at: backupURL)
    removeStaleBackups(for: targetURL, fileManager: fileManager)
  }
}

public func unloadEngineAgent(uid: uid_t = getuid()) {
  unloadEngineAgent(uid: uid, runLaunchctl: launchctlStatus)
}

public func unloadEngineAgent(
  uid: uid_t,
  runLaunchctl: ([String]) throws -> Int32
) {
  let domainLabel = "gui/\(uid)/\(EngineIdentity.xpcService)"
  _ = try? runLaunchctl(["bootout", domainLabel])
}

private func launchctlStatus(_ arguments: [String]) throws -> Int32 {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  process.waitUntilExit()
  return process.terminationStatus
}

private func removeStaleBackups(for targetURL: URL, fileManager: FileManager) {
  let parentURL = targetURL.deletingLastPathComponent()
  let backupPrefix = ".\(targetURL.lastPathComponent).backup-"
  guard
    let contents = try? fileManager.contentsOfDirectory(
      at: parentURL,
      includingPropertiesForKeys: nil
    )
  else {
    return
  }

  for url in contents where url.lastPathComponent.hasPrefix(backupPrefix) {
    try? fileManager.removeItem(at: url)
  }
}
