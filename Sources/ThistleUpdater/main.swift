import Darwin
import Foundation
import ThistleSupport

struct UpdaterArguments {
  let archiveURL: URL
  let targetURL: URL
  let bundleIdentifier: String
  let parentProcessID: pid_t
}

enum UpdaterError: Error {
  case missingArgument(String)
  case invalidParentProcessID
  case appNotFoundInArchive
  case commandFailed(String, Int32)
}

var fallbackLaunchURL: URL?
var extractionURLForCleanup: URL?
var replacementForRestore: AppUpdateReplacement?

do {
  let arguments = try parseArguments()
  fallbackLaunchURL = arguments.targetURL
  waitForParentToExit(arguments.parentProcessID)
  unloadEngineAgent()
  let extractedAppURL = try extractApp(from: arguments.archiveURL)
  let extractionURL = extractedAppURL.deletingLastPathComponent()
  extractionURLForCleanup = extractionURL
  try AppUpdateBundleValidator.validate(
    at: extractedAppURL,
    bundleIdentifier: arguments.bundleIdentifier
  )
  let replacement = try AppUpdateReplacement.perform(
    targetURL: arguments.targetURL,
    newAppURL: extractedAppURL
  )
  replacementForRestore = replacement
  try launchApp(at: arguments.targetURL)
  try? FileManager.default.removeItem(at: arguments.archiveURL)
  try? FileManager.default.removeItem(at: extractionURL)
  extractionURLForCleanup = nil
  replacement.discardBackup()
  replacementForRestore = nil
} catch {
  if let replacementForRestore {
    try? replacementForRestore.restore()
  }
  if let extractionURLForCleanup {
    try? FileManager.default.removeItem(at: extractionURLForCleanup)
  }
  if let fallbackLaunchURL {
    try? launchApp(at: fallbackLaunchURL)
  }
  FileHandle.standardError.write(Data("Update failed: \(error)\n".utf8))
  exit(1)
}

private func parseArguments() throws -> UpdaterArguments {
  let rawArguments = Array(CommandLine.arguments.dropFirst())

  func value(after key: String) throws -> String {
    guard let keyIndex = rawArguments.firstIndex(of: key),
      rawArguments.indices.contains(keyIndex + 1)
    else {
      throw UpdaterError.missingArgument(key)
    }
    return rawArguments[keyIndex + 1]
  }

  guard let parentProcessID = pid_t(try value(after: "--parent-pid")) else {
    throw UpdaterError.invalidParentProcessID
  }

  return UpdaterArguments(
    archiveURL: URL(fileURLWithPath: try value(after: "--archive")),
    targetURL: URL(fileURLWithPath: try value(after: "--target")),
    bundleIdentifier: try value(after: "--bundle-id"),
    parentProcessID: parentProcessID
  )
}

private func waitForParentToExit(_ processID: pid_t, timeout: TimeInterval = 30) {
  let deadline = Date().addingTimeInterval(timeout)

  while kill(processID, 0) == 0 {
    if Date() >= deadline {
      kill(processID, SIGTERM)
      usleep(500_000)
      if kill(processID, 0) == 0 {
        kill(processID, SIGKILL)
      }
      break
    }
    usleep(200_000)
  }
}

private func extractApp(from archiveURL: URL) throws -> URL {
  let extractionURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("thistle-update-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(
    at: extractionURL,
    withIntermediateDirectories: true
  )

  try runCommand(
    executablePath: "/usr/bin/ditto",
    arguments: [
      "-x",
      "-k",
      archiveURL.path,
      extractionURL.path,
    ]
  )

  let contents = try FileManager.default.contentsOfDirectory(
    at: extractionURL,
    includingPropertiesForKeys: nil
  )
  guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
    throw UpdaterError.appNotFoundInArchive
  }

  return appURL
}

private func launchApp(at targetURL: URL) throws {
  try runCommand(
    executablePath: "/usr/bin/open",
    arguments: [targetURL.path]
  )
}

private func runCommand(executablePath: String, arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executablePath)
  process.arguments = arguments
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    throw UpdaterError.commandFailed(executablePath, process.terminationStatus)
  }
}
