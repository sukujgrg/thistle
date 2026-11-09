#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  /// Layer-1 catalog contracts: every ConvertAction encodes a valid Gotenberg 9 request.
  struct ConvertActionContractTests {
    private static let bannedFieldNames: Set<String> = [
      "pdfa", "pdfua", "optimizeImages", "imageQuality", "splitSpan", "splitUnify",
      "rotateAngle", "rotatePages", "nativePageRanges", "generateDocumentOutline",
      "generateTaggedPdf", "waitWindowStatus", "nativePdfFormats", "firstPageOnLeft",
      "facturxVersion", "facturxXml", "embeds", "embedsMetadata", "watermarkSource",
      "stampSource", "merge", "flatten", "allowPrinting", "allowCopying",
    ]

    private static let expectedPathPrefixes = [
      "/forms/chromium/", "/forms/libreoffice/", "/forms/pdf/",
    ]

    private static let allIDs = ConvertAction.all.map(\.id)
    private static let finishingIDs = ConvertAction.all.filter { $0.composer == .finishing }.map(
      \.id)

    private static func action(_ id: String) throws -> ConvertAction {
      try #require(ConvertAction.all.first { $0.id == id })
    }

    @Test func catalogIDsAreUnique() {
      let ids = Self.allIDs
      #expect(Set(ids).count == ids.count)
    }

    @Test func catalogGroupsCoverEveryAction() {
      let grouped = Set(ConvertAction.grouped().flatMap(\.1).map(\.id))
      #expect(grouped == Set(Self.allIDs))
    }

    @Test(arguments: allIDs)
    func pathIsGotenbergNine(_ id: String) throws {
      let action = try Self.action(id)
      #expect(!action.path.contains("pdfengines"))
      #expect(Self.expectedPathPrefixes.contains { action.path.hasPrefix($0) })
      #expect(action.path.hasPrefix("/"))
      #expect(!action.title.isEmpty)
      #expect(!action.defaultFilename.isEmpty)
    }

    @Test(arguments: allIDs)
    func composerMatchesRouteKind(_ id: String) throws {
      let action = try Self.action(id)
      switch action.composer {
      case .stamps:
        #expect(action.path == "/forms/pdf/pipe")
        #expect(action.id == "pdf-stamp")
      case .finishing:
        #expect(
          action.path.hasPrefix("/forms/chromium/convert/")
            || action.path == "/forms/libreoffice/convert")
      case .fields:
        if action.id == "pdf-attach" {
          #expect(action.path == "/forms/pdf/pipe")
        }
        #expect(action.id != "pdf-stamp")
      }
    }

    @Test(arguments: allIDs)
    func seededFormSubmitsWithoutBannedFields(_ id: String) throws {
      let action = try Self.action(id)
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }

      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)

      #expect(form.canSubmit(action), "\(action.id) should submit with seeded fixtures")

      let fields = form.fieldsToSend(action)
      let banned = fields.map(\.name).filter { Self.bannedFieldNames.contains($0) }
      #expect(banned.isEmpty, "\(action.id) leaked G8 fields: \(banned)")

      let uploads = form.filesToSend(action)
      if action.files != nil || action.extraFiles.contains(where: { $0.required })
        || action.composer == .stamps || action.id == "pdf-attach" || action.id == "pdf-sign"
        || action.id == "pdf-insert"
      {
        #expect(!uploads.isEmpty, "\(action.id) should upload at least one file")
      }
      for upload in uploads {
        #expect(
          upload.field == "files",
          "\(action.id) should upload named assets under files, got \(upload.field)")
      }
    }

    @Test(arguments: finishingIDs)
    func finishingActionsOmitStagesUntilConfigured(_ id: String) throws {
      let action = try Self.action(id)
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      #expect(form.fieldsToSend(action).firstValue(for: "stages") == nil)

      form.finishing.optimize = true
      let stages = try #require(form.fieldsToSend(action).firstValue(for: "stages"))
      #expect(stages.contains(#""op":"optimize""#))
    }

    @Test func splitEncodesEveryOrRangesNotLegacySpan() throws {
      let action = try Self.action("pdf-split")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)

      form.values["splitMode"] = "intervals"
      form.values["every"] = "2"
      let intervalFields = form.fieldsToSend(action)
      #expect(intervalFields.firstValue(for: "every") == "2")
      #expect(intervalFields.firstValue(for: "ranges") == nil)
      #expect(intervalFields.firstValue(for: "splitMode") == nil)
      #expect(intervalFields.firstValue(for: "splitSpan") == nil)

      form.values["splitMode"] = "pages"
      form.values["ranges"] = "1-2,4"
      let pageFields = form.fieldsToSend(action)
      #expect(pageFields.firstValue(for: "every") == nil)
      #expect(pageFields.firstValue(for: "ranges") == #"["1-2","4"]"#)
    }

    @Test func rotateSendsAngleNotRotateAngle() throws {
      let action = try Self.action("pdf-rotate")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "angle") == "90")
      #expect(fields.firstValue(for: "rotateAngle") == nil)
    }

    @Test func encryptSendsPermissionsJSONAndPasswords() throws {
      let action = try Self.action("pdf-encrypt")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      form.values["userPassword"] = "secret"
      form.values["print"] = "false"
      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "userPassword") == "secret")
      let permissions = try #require(fields.firstValue(for: "permissions"))
      #expect(permissions.contains(#""print":false"#) || permissions.contains(#""print": false"#))
      #expect(fields.firstValue(for: "allowPrinting") == nil)
    }

    @Test func remediateAndValidateRequireProfile() throws {
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }

      for id in ["pdf-remediate", "pdf-validate"] {
        let action = try Self.action(id)
        var form = ActionForm(action: action)
        try workspace.seedFilesOnly(&form, for: action)
        form.values["profile"] = ""
        #expect(!form.canSubmit(action))
        form.values["profile"] = "PDF/A-2b"
        #expect(form.canSubmit(action))
        #expect(form.fieldsToSend(action).firstValue(for: "profile") == "PDF/A-2b")
      }
    }

    @Test func facturXRemediateNamesXMLUnderFiles() throws {
      let action = try Self.action("pdf-remediate")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      form.values["profile"] = "Factur-X"
      form.values["level"] = "EN 16931"
      let xml = try workspace.write("invoice.xml", contents: "<Invoice/>")
      form.extraFiles["xml"] = [xml]
      #expect(form.canSubmit(action))
      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "xml") == "invoice.xml")
      #expect(fields.firstValue(for: "level") == "EN 16931")
      #expect(form.filesToSend(action).map(\.field).allSatisfy { $0 == "files" })
    }

    @Test func stampPipeEncodesStagesOnly() throws {
      let action = try Self.action("pdf-stamp")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      let fields = form.fieldsToSend(action)
      #expect(fields.count == 1)
      #expect(fields[0].name == "stages")
      #expect(fields[0].value.contains(#""op":"stamp-text""#))
    }

    @Test func attachPipeEncodesAttachStagesAndFiles() throws {
      let action = try Self.action("pdf-attach")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      let fields = form.fieldsToSend(action)
      let stages = try #require(fields.firstValue(for: "stages"))
      #expect(stages.contains(#""op":"attach""#))
      #expect(stages.contains("note.txt"))
      #expect(form.filesToSend(action).map(\.field) == ["files", "files"])
    }

    @Test func signNamesCertificateFromUploadedFiles() throws {
      let action = try Self.action("pdf-sign")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "certificate") == "cert.p12")
      #expect(
        form.filesToSend(action).contains {
          $0.field == "files" && $0.url.lastPathComponent == "cert.p12"
        })
    }

    @Test func insertNamesSourceFromUploadedFiles() throws {
      let action = try Self.action("pdf-insert")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      #expect(form.fieldsToSend(action).firstValue(for: "source") == "annex.pdf")
      #expect(form.fieldsToSend(action).firstValue(for: "file") == nil)
    }

    @Test func metadataWriteUsesStandardInfoFields() throws {
      let action = try Self.action("pdf-metadata-write")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      try workspace.seed(&form, for: action)
      form.values["title"] = "Report"
      form.values["author"] = "Thistle"
      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "title") == "Report")
      #expect(fields.firstValue(for: "author") == "Thistle")
      #expect(fields.firstValue(for: "metadata") == nil)
    }

    @Test func libreOfficeNativePdfuaIsProfileString() throws {
      let action = try Self.action("libreoffice-convert")
      #expect(
        action.fields.contains { field in
          if case .picker(let options) = field.kind, field.key == "nativePdfua" {
            return options.contains("PDF/UA-1")
          }
          return false
        })
    }
  }

  // MARK: - Fixtures

  private final class FixtureWorkspace: @unchecked Sendable {
    let root: URL

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "thistle-contract-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
      try? FileManager.default.removeItem(at: root)
    }

    func write(_ name: String, contents: String = "fixture") throws -> URL {
      let url = root.appendingPathComponent(name)
      try Data(contents.utf8).write(to: url)
      return url
    }

    func seedFilesOnly(_ form: inout ActionForm, for action: ConvertAction) throws {
      guard let slot = action.files else { return }
      form.files = try mainFiles(for: action, slot: slot)
    }

    func seed(_ form: inout ActionForm, for action: ConvertAction) throws {
      if action.urlField {
        form.url = "https://example.com/page"
      }
      if let slot = action.files {
        form.files = try mainFiles(for: action, slot: slot)
      }
      for slot in action.extraFiles where slot.required || slot.minimumCount > 0
        || needsOptionalExtra(action: action, slot: slot)
      {
        form.extraFiles[slot.field] = try extraFiles(for: slot)
      }

      switch action.id {
      case "pdf-encrypt":
        form.values["userPassword"] = "secret"
      case "pdf-remediate", "pdf-validate":
        form.values["profile"] = "PDF/A-2b"
      case "pdf-metadata-write":
        form.values["title"] = "Title"
      case "pdf-bookmarks-write":
        form.values["bookmarks"] = #"[{"title":"One","pageNumber":1}]"#
      case "pdf-timestamp":
        form.values["url"] = "https://timestamp.example"
      case "pdf-detach":
        form.values["name"] = "attachment.xml"
      case "pdf-select", "pdf-delete":
        form.values["pages"] = "1"
      case "pdf-set-form":
        form.values["fields"] = #"{"agree":"Yes"}"#
      case "pdf-redact":
        form.values["regions"] = #"[{"page":1,"x":0,"y":0,"width":10,"height":10}]"#
      case "pdf-compose":
        form.values["placements"] =
          #"[{"source":"a.pdf","sourcePage":1,"page":1,"x":0,"y":0}]"#
      case "pdf-split":
        form.values["splitMode"] = "intervals"
        form.values["every"] = "1"
      default:
        break
      }
    }

    private func needsOptionalExtra(action: ConvertAction, slot: FileSlot) -> Bool {
      switch (action.id, slot.field) {
      case ("pdf-sign", "certificate"), ("pdf-insert", "insert"), ("pdf-attach", "attachments"):
        true
      default:
        false
      }
    }

    private func mainFiles(for action: ConvertAction, slot: FileSlot) throws -> [URL] {
      if action.id.contains("html") || action.id.contains("markdown") {
        var files = [try write("index.html", contents: "<html><body>Hi</body></html>")]
        if action.id.contains("markdown") {
          files.append(try write("doc.md", contents: "# Hi"))
        }
        return files
      }
      if action.group == .libreOffice {
        return [try write("report.docx")]
      }
      let count = max(slot.minimumCount, slot.allowsMultiple && action.id == "pdf-merge" ? 2 : 1)
      if action.id == "pdf-compose" {
        return [try write("a.pdf"), try write("b.pdf")]
      }
      return try (0..<count).map { index in
        let name = count == 1 ? "input.pdf" : "input-\(index).pdf"
        return try write(name)
      }
    }

    private func extraFiles(for slot: FileSlot) throws -> [URL] {
      switch slot.field {
      case "certificate":
        return [try write("cert.p12")]
      case "key":
        return [try write("key.pem")]
      case "insert":
        return [try write("annex.pdf")]
      case "attachments":
        return [try write("note.txt", contents: "note")]
      case "xml":
        return [try write("invoice.xml", contents: "<Invoice/>")]
      default:
        let ext = slot.extensions.sorted().first ?? "bin"
        return [try write("extra.\(ext)")]
      }
    }
  }
#endif
