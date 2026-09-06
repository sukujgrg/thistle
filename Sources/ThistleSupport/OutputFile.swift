import Foundation

public enum OutputFile: Sendable {
  public static func suggestedExtension(mime: String, data: Data) -> String {
    let type =
      mime.split(separator: ";").first.map(String.init)?.lowercased() ?? mime.lowercased()
    if type.contains("pdf") { return "pdf" }
    if type.contains("zip") { return "zip" }
    if type.contains("json") { return "json" }
    if type.contains("png") { return "png" }
    if type.contains("jpeg") || type.contains("jpg") { return "jpg" }
    if type.contains("webp") { return "webp" }
    if isJSON(data) { return "json" }
    if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
    if isWebP(data) { return "webp" }
    if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
      return "zip"
    }
    return "bin"
  }

  public static func filename(basename: String, ext: String) -> String {
    let name = basename.trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = ".\(ext)"
    if name.lowercased().hasSuffix(suffix.lowercased()) {
      return name
    }
    return name.isEmpty ? "output\(suffix)" : "\(name)\(suffix)"
  }

  public static func suggestedBasename(
    fromInputBasename name: String?,
    inputExtension: String?,
    outputExtension: String?,
    defaultFilename: String
  ) -> String {
    guard let name, !name.isEmpty else { return defaultFilename }
    let inputExt =
      inputExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let outputExt =
      outputExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let sameType = !inputExt.isEmpty && inputExt == outputExt
    guard sameType else { return name }
    let suffix = defaultFilename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !suffix.isEmpty else { return name }
    if name.lowercased().hasSuffix("-\(suffix.lowercased())") {
      return name
    }
    return "\(name)-\(suffix)"
  }

  public static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
    let a = lhs.standardizedFileURL
    let b = rhs.standardizedFileURL
    if a.path(percentEncoded: false) == b.path(percentEncoded: false) {
      return true
    }
    guard
      let aID = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey])
        .fileResourceIdentifier,
      let bID = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey])
        .fileResourceIdentifier
    else {
      return false
    }
    return aID.isEqual(bID)
  }

  public static func place(_ source: URL, at destination: URL, moving: Bool) throws {
    let fm = FileManager.default
    let sourceURL = source.standardizedFileURL
    let destURL = destination.standardizedFileURL
    if sameFile(sourceURL, destURL) {
      return
    }

    if moving, !fm.fileExists(atPath: destURL.path(percentEncoded: false)) {
      try fm.moveItem(at: sourceURL, to: destURL)
      return
    }

    let temp = destURL.deletingLastPathComponent().appendingPathComponent(
      ".\(UUID().uuidString)-\(destURL.lastPathComponent)")
    try fm.copyItem(at: sourceURL, to: temp)
    do {
      if fm.fileExists(atPath: destURL.path(percentEncoded: false)) {
        _ = try fm.replaceItemAt(destURL, withItemAt: temp)
      } else {
        try fm.moveItem(at: temp, to: destURL)
      }
    } catch {
      try? fm.removeItem(at: temp)
      throw error
    }
    if moving, fm.fileExists(atPath: sourceURL.path(percentEncoded: false)),
      !sameFile(sourceURL, destURL)
    {
      try? fm.removeItem(at: sourceURL)
    }
  }

  public static func clearDirectory(_ directory: URL, keeping keep: URL? = nil) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
    let items =
      (try? fm.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
    let keepPath = keep.map { $0.standardizedFileURL.path(percentEncoded: false) }
    for item in items {
      if let keepPath, item.standardizedFileURL.path(percentEncoded: false) == keepPath {
        continue
      }
      try? fm.removeItem(at: item)
    }
  }

  static func isJSON(_ data: Data) -> Bool {
    guard let first = data.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D })
    else {
      return false
    }
    return first == 0x7B || first == 0x5B
  }

  private static func isWebP(_ data: Data) -> Bool {
    guard data.count >= 12 else { return false }
    return data.starts(with: [0x52, 0x49, 0x46, 0x46])
      && data[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50])
  }
}
