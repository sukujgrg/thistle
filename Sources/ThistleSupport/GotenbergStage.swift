import Foundation

/// One Gotenberg 9 PDF stage. Encodes to the JSON object the API expects in `stages`.
public enum GotenbergStage: Equatable, Sendable {
  case merge
  case splitEvery(Int)
  case splitRanges([String])
  case select(pages: String)
  case delete(pages: String)
  case insert(source: String, at: Int?, sourcePages: String?)
  case compose(paperSize: String?, paperWidth: Double?, paperHeight: Double?, placements: AnyJSON)
  case rotate(angle: Int, pages: String?)
  case stampText(PDFStamp.TextStage)
  case stampImage(PDFStamp.ImageStage)
  case stampPDF(PDFStamp.PDFStage)
  case setMetadata(PDFDocumentInfo)
  case setBookmarks(AnyJSON)
  case setForm(fields: AnyJSON)
  case flattenForm
  case flattenTransparency
  case convertColors(space: String)
  case redact(regions: AnyJSON)
  case autotag
  case attach(file: String)
  case detach(name: String)
  case extractAttachments(name: String?)
  case extractText(pages: String?, invisible: Bool, artifacts: Bool, annotations: Bool)
  case optimize(OptimizeOptions)
  case encrypt(EncryptOptions)
  case decrypt(password: String)
  case remediate(RemediateOptions)
  case sign(certificate: String, password: String?, reason: String?, location: String?)
  case timestamp(url: String)
  case render(format: String, dpi: Double?, pages: String?)

  public var op: String {
    switch self {
    case .merge: "merge"
    case .splitEvery, .splitRanges: "split"
    case .select: "select"
    case .delete: "delete"
    case .insert: "insert"
    case .compose: "compose"
    case .rotate: "rotate"
    case .stampText: "stamp-text"
    case .stampImage: "stamp-image"
    case .stampPDF: "stamp-pdf"
    case .setMetadata: "set-metadata"
    case .setBookmarks: "set-bookmarks"
    case .setForm: "set-form"
    case .flattenForm: "flatten-form"
    case .flattenTransparency: "flatten-transparency"
    case .convertColors: "convert-colors"
    case .redact: "redact"
    case .autotag: "autotag"
    case .attach: "attach"
    case .detach: "detach"
    case .extractAttachments: "extract-attachments"
    case .extractText: "extract-text"
    case .optimize: "optimize"
    case .encrypt: "encrypt"
    case .decrypt: "decrypt"
    case .remediate: "remediate"
    case .sign: "sign"
    case .timestamp: "timestamp"
    case .render: "render"
    }
  }

  public func jsonObject() -> [String: Any] {
    var object: [String: Any] = ["op": op]
    switch self {
    case .merge, .flattenForm, .flattenTransparency, .autotag:
      break
    case .splitEvery(let every):
      object["every"] = every
    case .splitRanges(let ranges):
      object["ranges"] = ranges
    case .select(let pages), .delete(let pages):
      object["pages"] = pages
    case .insert(let source, let at, let sourcePages):
      object["source"] = source
      if let at { object["at"] = at }
      if let sourcePages, !sourcePages.isEmpty { object["sourcePages"] = sourcePages }
    case .compose(let paperSize, let paperWidth, let paperHeight, let placements):
      if let paperSize { object["paperSize"] = paperSize }
      if let paperWidth { object["paperWidth"] = paperWidth }
      if let paperHeight { object["paperHeight"] = paperHeight }
      object["placements"] = placements.value
    case .rotate(let angle, let pages):
      object["angle"] = angle
      if let pages, !pages.isEmpty { object["pages"] = pages }
    case .stampText(let stamp):
      object.merge(stamp.jsonObject()) { _, new in new }
    case .stampImage(let stamp):
      object.merge(stamp.jsonObject()) { _, new in new }
    case .stampPDF(let stamp):
      object.merge(stamp.jsonObject()) { _, new in new }
    case .setMetadata(let info):
      object.merge(info.jsonObject()) { _, new in new }
    case .setBookmarks(let bookmarks):
      object["bookmarks"] = bookmarks.value
    case .setForm(let fields):
      object["fields"] = fields.value
    case .convertColors(let space):
      object["space"] = space
    case .redact(let regions):
      object["regions"] = regions.value
    case .attach(let file):
      object["file"] = file
    case .detach(let name):
      object["name"] = name
    case .extractAttachments(let name):
      if let name, !name.isEmpty { object["name"] = name }
    case .extractText(let pages, let invisible, let artifacts, let annotations):
      if let pages, !pages.isEmpty { object["pages"] = pages }
      if invisible { object["invisible"] = true }
      if artifacts { object["artifacts"] = true }
      if annotations { object["annotations"] = true }
    case .optimize(let options):
      object.merge(options.jsonObject()) { _, new in new }
    case .encrypt(let options):
      object.merge(options.jsonObject()) { _, new in new }
    case .decrypt(let password):
      object["password"] = password
    case .remediate(let options):
      object.merge(options.jsonObject()) { _, new in new }
    case .sign(let certificate, let password, let reason, let location):
      object["certificate"] = certificate
      if let password, !password.isEmpty { object["password"] = password }
      if let reason, !reason.isEmpty { object["reason"] = reason }
      if let location, !location.isEmpty { object["location"] = location }
    case .timestamp(let url):
      object["url"] = url
    case .render(let format, let dpi, let pages):
      object["format"] = format
      if let dpi { object["dpi"] = dpi }
      if let pages, !pages.isEmpty { object["pages"] = pages }
    }
    return object
  }

  public static func encodeJSON(_ stages: [GotenbergStage]) throws -> String {
    let objects = stages.map { $0.jsonObject() }
    let data = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else {
      throw EngineError.operationFailed("Could not encode stages JSON.")
    }
    return text
  }
}

/// Type-erased JSON value for bookmarks, form fields, placements, and redaction regions.
public struct AnyJSON: Equatable, @unchecked Sendable {
  public let value: Any

  public init(_ value: Any) {
    self.value = value
  }

  public static func == (lhs: AnyJSON, rhs: AnyJSON) -> Bool {
    switch (lhs.value, rhs.value) {
    case (let a as NSArray, let b as NSArray): a.isEqual(b)
    case (let a as NSDictionary, let b as NSDictionary): a.isEqual(b)
    case (let a as String, let b as String): a == b
    case (let a as NSNumber, let b as NSNumber): a.isEqual(to: b)
    case (is NSNull, is NSNull): true
    default: false
    }
  }

  public static func parse(_ raw: String) -> AnyJSON? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data)
    else { return nil }
    return AnyJSON(object)
  }
}

public struct PDFDocumentInfo: Equatable, Sendable {
  public var title = ""
  public var author = ""
  public var subject = ""
  public var keywords = ""
  public var creator = ""
  public var producer = ""
  public var creationDate = ""
  public var modDate = ""

  public init() {}

  public var isEmpty: Bool {
    [title, author, subject, keywords, creator, producer, creationDate, modDate]
      .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  public func jsonObject() -> [String: Any] {
    var object: [String: Any] = [:]
    func put(_ key: String, _ value: String) {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { object[key] = trimmed }
    }
    put("title", title)
    put("author", author)
    put("subject", subject)
    put("keywords", keywords)
    put("creator", creator)
    put("producer", producer)
    put("creationDate", creationDate)
    put("modDate", modDate)
    return object
  }

  public func formFields() -> [MultipartField] {
    jsonObject().compactMap { key, value in
      guard let string = value as? String else { return nil }
      return MultipartField(key, string)
    }.sorted { $0.name < $1.name }
  }
}

public struct OptimizeOptions: Equatable, Sendable {
  public var objectStreams = true
  public var dedup = true
  public var recompressImages = true
  public var subsetFonts = true

  public init() {}

  public func jsonObject() -> [String: Any] {
    var object: [String: Any] = [:]
    if !objectStreams { object["objectStreams"] = false }
    if !dedup { object["dedup"] = false }
    if !recompressImages { object["recompressImages"] = false }
    if !subsetFonts { object["subsetFonts"] = false }
    return object
  }

  public func formFields() -> [MultipartField] {
    [
      MultipartField("objectStreams", objectStreams ? "true" : "false"),
      MultipartField("dedup", dedup ? "true" : "false"),
      MultipartField("recompressImages", recompressImages ? "true" : "false"),
      MultipartField("subsetFonts", subsetFonts ? "true" : "false"),
    ]
  }
}

public struct EncryptOptions: Equatable, Sendable {
  public var userPassword = ""
  public var ownerPassword = ""
  public var algorithm = "aes256"
  public var print = true
  public var printHighQuality = true
  public var modifyContent = true
  public var extractText = true
  public var modifyAnnotations = true
  public var fillForms = true
  public var assemble = true

  public init() {}

  public var hasPassword: Bool {
    !userPassword.isEmpty || !ownerPassword.isEmpty
  }

  public func jsonObject() -> [String: Any] {
    var object: [String: Any] = [:]
    if !userPassword.isEmpty { object["userPassword"] = userPassword }
    if !ownerPassword.isEmpty { object["ownerPassword"] = ownerPassword }
    if algorithm != "aes256" { object["algorithm"] = algorithm }
    var permissions: [String: Bool] = [:]
    if !print { permissions["print"] = false }
    if !printHighQuality { permissions["printHighQuality"] = false }
    if !modifyContent { permissions["modifyContent"] = false }
    if !extractText { permissions["extractText"] = false }
    if !modifyAnnotations { permissions["modifyAnnotations"] = false }
    if !fillForms { permissions["fillForms"] = false }
    if !assemble { permissions["assemble"] = false }
    if !permissions.isEmpty { object["permissions"] = permissions }
    return object
  }

  public func formFields() throws -> [MultipartField] {
    var fields: [MultipartField] = []
    if !userPassword.isEmpty { fields.append(MultipartField("userPassword", userPassword)) }
    if !ownerPassword.isEmpty { fields.append(MultipartField("ownerPassword", ownerPassword)) }
    if algorithm != "aes256" { fields.append(MultipartField("algorithm", algorithm)) }
    let permissions = jsonObject()["permissions"]
    if let permissions {
      let data = try JSONSerialization.data(withJSONObject: permissions, options: [.sortedKeys])
      if let text = String(data: data, encoding: .utf8) {
        fields.append(MultipartField("permissions", text))
      }
    }
    return fields
  }
}

public struct RemediateOptions: Equatable, Sendable {
  public var profiles: [String] = []
  public var language = "en"
  public var aggressive = false
  public var figureAltText = ""
  public var xmlFilename: String?
  public var level = ""
  public var documentType = "INVOICE"

  public init() {}

  public var isActive: Bool { !profiles.isEmpty }

  public func jsonObject() -> [String: Any] {
    var object: [String: Any] = [:]
    if profiles.count == 1 {
      object["profile"] = profiles[0]
    } else if profiles.count > 1 {
      object["profile"] = profiles
    }
    if language != "en" { object["language"] = language }
    if aggressive { object["aggressive"] = true }
    let alt = figureAltText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !alt.isEmpty { object["figureAltText"] = alt }
    if let xmlFilename { object["xml"] = xmlFilename }
    if !level.isEmpty { object["level"] = level }
    if profiles.contains("Factur-X"), documentType != "INVOICE" {
      object["documentType"] = documentType
    }
    return object
  }

  public func formFields() throws -> [MultipartField] {
    var fields: [MultipartField] = []
    if profiles.count == 1 {
      fields.append(MultipartField("profile", profiles[0]))
    } else if profiles.count > 1 {
      let data = try JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys])
      if let text = String(data: data, encoding: .utf8) {
        fields.append(MultipartField("profile", text))
      }
    }
    if language != "en" { fields.append(MultipartField("language", language)) }
    if aggressive { fields.append(MultipartField("aggressive", "true")) }
    let alt = figureAltText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !alt.isEmpty { fields.append(MultipartField("figureAltText", alt)) }
    if let xmlFilename { fields.append(MultipartField("xml", xmlFilename)) }
    if !level.isEmpty { fields.append(MultipartField("level", level)) }
    if profiles.contains("Factur-X"), documentType != "INVOICE" {
      fields.append(MultipartField("documentType", documentType))
    }
    return fields
  }
}

/// Optional post-processing for Chromium and LibreOffice convert routes.
public struct ConversionFinishing: Equatable, Sendable {
  public var merge = false
  public var flattenForm = false
  public var optimize = false
  public var optimizeOptions = OptimizeOptions()
  public var remediate = RemediateOptions()
  public var encrypt = EncryptOptions()
  public var metadata = PDFDocumentInfo()
  public var splitMode = ""  // "", "intervals", "pages"
  public var splitEvery = "1"
  public var splitRanges = ""

  public init() {}

  public var stages: [GotenbergStage] {
    var out: [GotenbergStage] = []
    if merge { out.append(.merge) }
    switch splitMode {
    case "intervals":
      if let every = Int(splitEvery.trimmingCharacters(in: .whitespacesAndNewlines)), every > 0 {
        out.append(.splitEvery(every))
      }
    case "pages":
      let ranges =
        splitRanges
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if !ranges.isEmpty { out.append(.splitRanges(ranges)) }
    default:
      break
    }
    if flattenForm { out.append(.flattenForm) }
    if !metadata.isEmpty { out.append(.setMetadata(metadata)) }
    if remediate.isActive { out.append(.remediate(remediate)) }
    if optimize { out.append(.optimize(optimizeOptions)) }
    if encrypt.hasPassword { out.append(.encrypt(encrypt)) }
    return out
  }

  public var validationMessage: String? {
    if splitMode == "intervals" {
      let raw = splitEvery.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let every = Int(raw), every > 0 else {
        return "Split every needs a positive number of pages."
      }
    }
    if splitMode == "pages" {
      let ranges =
        splitRanges
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if ranges.isEmpty {
        return "Split by pages needs at least one range, such as 1-3 or 5."
      }
    }
    return nil
  }
}

public struct RemediationReport: Equatable, Sendable {
  public let residual: Int?
  public let rolledBack: Int?

  public init(residual: Int?, rolledBack: Int?) {
    self.residual = residual
    self.rolledBack = rolledBack
  }

  public init(http: HTTPURLResponse) {
    residual = Int(http.value(forHTTPHeaderField: "Gotenberg-Remediation-Residual") ?? "")
    rolledBack = Int(http.value(forHTTPHeaderField: "Gotenberg-Remediation-Rolled-Back") ?? "")
  }

  public var summary: String? {
    guard residual != nil || rolledBack != nil else { return nil }
    var parts: [String] = []
    if let residual {
      parts.append(
        residual == 0
          ? "Conforms to the requested profile."
          : "\(residual) residual violation\(residual == 1 ? "" : "s").")
    }
    if let rolledBack, rolledBack > 0 {
      parts.append(
        "\(rolledBack) fix\(rolledBack == 1 ? "" : "es") rolled back to keep page content.")
    }
    return parts.joined(separator: " ")
  }
}
