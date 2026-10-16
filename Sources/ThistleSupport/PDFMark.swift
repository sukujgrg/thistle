import Foundation

public struct PDFMark: Identifiable, Equatable, Sendable {
  public enum Source: String, CaseIterable, Identifiable, Sendable {
    case text, image, pdf
    public var id: String { rawValue }
    public var label: String {
      switch self {
      case .text: "Text"
      case .image: "Image"
      case .pdf: "PDF"
      }
    }
  }

  public let id: UUID
  public var source: Source = .text
  public var text: String
  public var pages = ""
  public var options = ""
  public var files: [URL] = []

  public init(id: UUID = UUID(), text: String = "") {
    self.id = id
    self.text = text
  }

  public var validationMessage: String? {
    if source == .text {
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Enter the mark text."
      }
    } else {
      let extensions: Set<String> = source == .pdf ? ["pdf"] : ["png", "jpg", "jpeg", "webp"]
      guard files.count == 1, let file = files.first,
        extensions.contains(file.pathExtension.lowercased()),
        (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
      else { return "Choose one \(source == .pdf ? "PDF" : "PNG, JPEG, or WebP") file." }
    }
    if !options.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      guard let data = options.data(using: .utf8),
        (try? JSONSerialization.jsonObject(with: data)) is [String: String]
      else { return "Options must be a JSON object with string values." }
    }
    return nil
  }

  public func fields(prefix: String) -> [MultipartField] {
    // Emit every parallel-list value, even when empty, so settings never shift
    // onto another mark. File marks consume uploaded files in order.
    [
      MultipartField("\(prefix)Source", source.rawValue),
      MultipartField("\(prefix)Expression", source == .text ? text : ""),
      MultipartField("\(prefix)Pages", pages.trimmingCharacters(in: .whitespacesAndNewlines)),
      MultipartField("\(prefix)Options", options.trimmingCharacters(in: .whitespacesAndNewlines)),
    ]
  }
}
