import Foundation

/// One ordered stamp for Gotenberg 9 (`stamp-text`, `stamp-image`, or `stamp-pdf`).
public struct PDFStamp: Identifiable, Equatable, Sendable {
  public enum Kind: String, CaseIterable, Identifiable, Sendable {
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

  public static let standardFonts = [
    "Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique",
    "Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic",
    "Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique",
    "Symbol", "ZapfDingbats",
  ]

  public let id: UUID
  public var kind: Kind = .text
  public var text = "APPROVED"
  public var pages = "all"
  public var x = "72"
  public var y = "72"
  public var fontSize = "24"
  public var font = "Helvetica"
  public var color = "#C00000"
  public var opacity = "0.4"
  public var rotation = "30"
  public var scale = "1"
  public var sourcePage = "1"
  public var files: [URL] = []

  public init(id: UUID = UUID(), text: String = "APPROVED") {
    self.id = id
    self.text = text
  }

  public var validationMessage: String? {
    switch kind {
    case .text:
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Enter the stamp text."
      }
    case .image:
      guard files.count == 1, let file = files.first,
        ["png", "jpg", "jpeg"].contains(file.pathExtension.lowercased()),
        (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
      else { return "Choose one PNG or JPEG file." }
    case .pdf:
      guard files.count == 1, let file = files.first,
        file.pathExtension.lowercased() == "pdf",
        (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
      else { return "Choose one PDF file." }
    }
    if pages.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Pages cannot be empty. Use all, odd, even, or a range such as 1-3."
    }
    for (label, raw) in [("X", x), ("Y", y), ("Font size", fontSize), ("Opacity", opacity),
      ("Rotation", rotation), ("Scale", scale)]
    {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let value = Double(trimmed) else { return "\(label) must be a number." }
      if label == "Font size", value <= 0 { return "Font size must be greater than 0." }
      if label == "Opacity", value < 0 || value > 1 {
        return "Opacity must be between 0 and 1."
      }
      if label == "Scale", value <= 0 { return "Scale must be greater than 0." }
    }
    if kind == .pdf {
      let trimmed = sourcePage.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let page = Int(trimmed), page > 0 else {
        return "Source page must be a positive integer."
      }
    }
    return nil
  }

  /// Filename referenced from the stage when the stamp needs an uploaded file.
  public func assetFilename(index: Int) -> String? {
    guard kind != .text, let file = files.first else { return nil }
    let ext = file.pathExtension.isEmpty ? "bin" : file.pathExtension.lowercased()
    return "stamp-\(index).\(ext)"
  }

  public func stage(assetFilename: String?) -> GotenbergStage {
    let pagesValue = pages.trimmingCharacters(in: .whitespacesAndNewlines)
    let xValue = Double(x) ?? 0
    let yValue = Double(y) ?? 0
    let opacityValue = Double(opacity) ?? 0
    let rotationValue = Double(rotation) ?? 0
    switch kind {
    case .text:
      return .stampText(
        TextStage(
          text: text.trimmingCharacters(in: .whitespacesAndNewlines),
          pages: pagesValue,
          x: xValue,
          y: yValue,
          fontSize: Double(fontSize) ?? 12,
          font: font,
          color: color.trimmingCharacters(in: .whitespacesAndNewlines),
          opacity: opacityValue,
          rotation: rotationValue
        ))
    case .image:
      return .stampImage(
        ImageStage(
          file: assetFilename ?? "",
          pages: pagesValue,
          x: xValue,
          y: yValue,
          scale: Double(scale) ?? 1,
          opacity: opacityValue,
          rotation: rotationValue
        ))
    case .pdf:
      return .stampPDF(
        PDFStage(
          file: assetFilename ?? "",
          sourcePage: Int(sourcePage) ?? 1,
          pages: pagesValue,
          x: xValue,
          y: yValue,
          scale: Double(scale) ?? 1,
          opacity: opacityValue,
          rotation: rotationValue
        ))
    }
  }

  public struct TextStage: Equatable, Sendable {
    public var text: String
    public var pages: String
    public var x: Double
    public var y: Double
    public var fontSize: Double
    public var font: String
    public var color: String
    public var opacity: Double
    public var rotation: Double

    public func jsonObject() -> [String: Any] {
      var object: [String: Any] = [
        "text": text,
        "pages": pages,
        "x": x,
        "y": y,
        "fontSize": fontSize,
        "font": font,
        "color": color,
        "rotation": rotation,
      ]
      if opacity > 0 { object["opacity"] = opacity }
      return object
    }
  }

  public struct ImageStage: Equatable, Sendable {
    public var file: String
    public var pages: String
    public var x: Double
    public var y: Double
    public var scale: Double
    public var opacity: Double
    public var rotation: Double

    public func jsonObject() -> [String: Any] {
      var object: [String: Any] = [
        "file": file,
        "pages": pages,
        "x": x,
        "y": y,
        "scale": scale,
        "rotation": rotation,
      ]
      if opacity > 0 { object["opacity"] = opacity }
      return object
    }
  }

  public struct PDFStage: Equatable, Sendable {
    public var file: String
    public var sourcePage: Int
    public var pages: String
    public var x: Double
    public var y: Double
    public var scale: Double
    public var opacity: Double
    public var rotation: Double

    public func jsonObject() -> [String: Any] {
      var object: [String: Any] = [
        "file": file,
        "sourcePage": sourcePage,
        "pages": pages,
        "x": x,
        "y": y,
        "scale": scale,
        "rotation": rotation,
      ]
      if opacity > 0 { object["opacity"] = opacity }
      return object
    }
  }
}
