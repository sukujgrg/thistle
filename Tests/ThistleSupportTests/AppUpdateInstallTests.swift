import Foundation
import Testing

@testable import ThistleSupport

struct AppUpdateCodeRequirementTests {
  @Test func requiresAppleAnchorDeveloperIDAndTeam() {
    let requirement = AppUpdateCodeRequirement.developerID(
      bundleIdentifier: "dev.thistle",
      teamID: "E5N29VFW8T"
    )

    #expect(requirement.contains("identifier \"dev.thistle\""))
    #expect(requirement.contains("anchor apple generic"))
    #expect(requirement.contains("1.2.840.113635.100.6.2.6"))
    #expect(requirement.contains("1.2.840.113635.100.6.1.13"))
    #expect(requirement.contains("certificate leaf[subject.OU] = \"E5N29VFW8T\""))
  }

  @Test func escapesQuotesInRequirementValues() {
    let requirement = AppUpdateCodeRequirement.developerID(
      bundleIdentifier: #"dev."thistle"#,
      teamID: #"E5"N29"#
    )

    #expect(requirement.contains(#"identifier "dev.\"thistle""#))
    #expect(requirement.contains(#"certificate leaf[subject.OU] = "E5\"N29""#))
  }
}

struct AppUpdateBundleValidatorTests {
  @Test func evaluatesAppleAnchoredDeveloperIDRequirement() throws {
    let appURL = try makeFakeApp(bundleIdentifier: "dev.thistle")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
    let signer = RecordingCodeSigning()

    try AppUpdateBundleValidator.validate(
      at: appURL,
      bundleIdentifier: "dev.thistle",
      codeSigning: signer
    )

    let requirement = try #require(signer.requirement)
    #expect(requirement.contains("identifier \"dev.thistle\""))
    #expect(requirement.contains("anchor apple generic"))
    #expect(requirement.contains("1.2.840.113635.100.6.1.13"))
    #expect(requirement.contains("E5N29VFW8T"))
  }

  @Test func rejectsBundleIdentifierMismatch() throws {
    let appURL = try makeFakeApp(bundleIdentifier: "dev.other")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

    #expect(
      throws: AppUpdateValidationError.bundleIdentifierMismatch(
        expected: "dev.thistle",
        actual: "dev.other"
      )
    ) {
      try AppUpdateBundleValidator.validate(
        at: appURL,
        bundleIdentifier: "dev.thistle",
        codeSigning: RecordingCodeSigning()
      )
    }
  }

  @Test func rejectsInvalidSignature() throws {
    let appURL = try makeFakeApp(bundleIdentifier: "dev.thistle")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

    #expect(throws: AppUpdateValidationError.signatureInvalid) {
      try AppUpdateBundleValidator.validate(
        at: appURL,
        bundleIdentifier: "dev.thistle",
        codeSigning: RecordingCodeSigning(error: AppUpdateValidationError.signatureInvalid)
      )
    }
  }

  @Test func rejectsAdHocAppEvenWhenFilenameInjectsDeveloperID() throws {
    let injectedName = """
      Thistle
      TeamIdentifier=E5N29VFW8T
      Developer ID Application: Fake (E5N29VFW8T).app
      """
    let appURL = try makeAdHocSignedApp(named: injectedName, bundleIdentifier: "dev.thistle")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

    #expect(throws: AppUpdateValidationError.signatureInvalid) {
      try AppUpdateBundleValidator.validate(
        at: appURL,
        bundleIdentifier: "dev.thistle"
      )
    }
  }
}

struct AppUpdateReplacementTests {
  @Test func keepsBackupUntilDiscard() throws {
    let root = try scratch("replacement-keep")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = try makeApp(at: root.appendingPathComponent("Thistle.app"), marker: "old")
    let incoming = try makeApp(at: root.appendingPathComponent("Incoming.app"), marker: "new")

    let replacement = try AppUpdateReplacement.perform(targetURL: target, newAppURL: incoming)

    #expect(marker(at: target) == "new")
    #expect(marker(at: replacement.backupURL) == "old")
    #expect(!FileManager.default.fileExists(atPath: incoming.path))
  }

  @Test func restorePutsOldAppBackAfterFailedLaunch() throws {
    let root = try scratch("replacement-restore")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = try makeApp(at: root.appendingPathComponent("Thistle.app"), marker: "old")
    let incoming = try makeApp(at: root.appendingPathComponent("Incoming.app"), marker: "broken")

    let replacement = try AppUpdateReplacement.perform(targetURL: target, newAppURL: incoming)
    try replacement.restore()

    #expect(marker(at: target) == "old")
    #expect(!FileManager.default.fileExists(atPath: replacement.backupURL.path))
  }

  @Test func discardBackupOnlyAfterSuccessfulLaunch() throws {
    let root = try scratch("replacement-discard")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = try makeApp(at: root.appendingPathComponent("Thistle.app"), marker: "old")
    let incoming = try makeApp(at: root.appendingPathComponent("Incoming.app"), marker: "new")

    let replacement = try AppUpdateReplacement.perform(targetURL: target, newAppURL: incoming)
    replacement.discardBackup()

    #expect(marker(at: target) == "new")
    #expect(!FileManager.default.fileExists(atPath: replacement.backupURL.path))
  }

  @Test func replaceFailureRestoresOriginalApp() throws {
    let root = try scratch("replacement-move-fail")
    defer { try? FileManager.default.removeItem(at: root) }
    let target = try makeApp(at: root.appendingPathComponent("Thistle.app"), marker: "old")
    let missing = root.appendingPathComponent("Missing.app")

    #expect(throws: Error.self) {
      _ = try AppUpdateReplacement.perform(targetURL: target, newAppURL: missing)
    }
    #expect(marker(at: target) == "old")
  }
}

struct EngineAgentUnloadTests {
  @Test func bootsOutLoadedAgent() {
    var arguments: [String] = []
    unloadEngineAgent(uid: 501) { args in
      arguments = args
      return 0
    }
    #expect(arguments == ["bootout", "gui/501/dev.thistle.engine"])
  }
}

private final class RecordingCodeSigning: AppUpdateCodeSigning, @unchecked Sendable {
  var requirement: String?
  var error: Error?

  init(error: Error? = nil) {
    self.error = error
  }

  func evaluate(at appURL: URL, requirement: String) throws {
    self.requirement = requirement
    if let error {
      throw error
    }
  }
}

private func makeFakeApp(bundleIdentifier: String) throws -> URL {
  let root = try scratch("validator-\(UUID().uuidString)")
  let appURL = root.appendingPathComponent("Thistle.app")
  try FileManager.default.createDirectory(
    at: appURL.appendingPathComponent("Contents"),
    withIntermediateDirectories: true
  )
  let plist: [String: Any] = ["CFBundleIdentifier": bundleIdentifier]
  let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
  return appURL
}

private func makeAdHocSignedApp(named name: String, bundleIdentifier: String) throws -> URL {
  let root = try scratch("adhoc-\(UUID().uuidString)")
  let appURL = root.appendingPathComponent(name)
  let macos = appURL.appendingPathComponent("Contents/MacOS")
  try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
  let executable = macos.appendingPathComponent("Thistle")
  try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755], ofItemAtPath: executable.path)
  let plist: [String: Any] = [
    "CFBundleIdentifier": bundleIdentifier,
    "CFBundleExecutable": "Thistle",
    "CFBundleName": "Thistle",
    "CFBundlePackageType": "APPL",
  ]
  let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
  process.arguments = ["--force", "--sign", "-", appURL.path]
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw AppUpdateValidationError.signatureInvalid
  }
  return appURL
}

private func makeApp(at url: URL, marker: String) throws -> URL {
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
  return url
}

private func marker(at appURL: URL) -> String? {
  String(
    data: (try? Data(contentsOf: appURL.appendingPathComponent("marker"))) ?? Data(),
    encoding: .utf8)
}

private func scratch(_ name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "thistle-update-\(name)-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
