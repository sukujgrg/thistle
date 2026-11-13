#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  /// Layer-2 ActionForm gates and encode edges that Layer-1 seeded contracts do not cover.
  struct ActionFormValidationTests {
    private static func action(_ id: String) throws -> ConvertAction {
      try #require(ConvertAction.all.first { $0.id == id })
    }

    @Test func urlRequiresHTTPSchemeAndHost() throws {
      let action = try Self.action("chromium-url-pdf")
      var form = ActionForm(action: action)

      form.url = ""
      #expect(!form.canSubmit(action))
      form.url = "not-a-url"
      #expect(!form.canSubmit(action))
      form.url = "file:///tmp/page.html"
      #expect(!form.canSubmit(action))
      form.url = "https://"
      #expect(!form.canSubmit(action))
      form.url = "https://example.com/page"
      #expect(form.canSubmit(action))
    }

    @Test func encryptRequiresPassword() throws {
      let action = try Self.action("pdf-encrypt")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      form.values["userPassword"] = ""
      form.values["ownerPassword"] = ""
      #expect(!form.canSubmit(action))

      form.values["userPassword"] = "secret"
      #expect(form.canSubmit(action))

      form.values["userPassword"] = ""
      form.values["ownerPassword"] = "owner"
      #expect(form.canSubmit(action))
    }

    @Test func metadataWriteRequiresAtLeastOneInfoField() throws {
      let action = try Self.action("pdf-metadata-write")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      for key in [
        "title", "author", "subject", "keywords", "creator", "producer", "creationDate", "modDate",
      ] {
        form.values[key] = ""
      }
      #expect(!form.canSubmit(action))

      form.values["author"] = "Thistle"
      #expect(form.canSubmit(action))
    }

    @Test func bookmarksWriteRejectsEmptyAndInvalidJSON() throws {
      let action = try Self.action("pdf-bookmarks-write")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      form.values["bookmarks"] = ""
      #expect(!form.canSubmit(action))
      form.values["bookmarks"] = "[]"
      #expect(!form.canSubmit(action))
      form.values["bookmarks"] = "{}"
      #expect(!form.canSubmit(action))
      form.values["bookmarks"] = #"{"title":"#
      #expect(!form.canSubmit(action))
      form.values["bookmarks"] = #"[{"title":"One","pageNumber":1}]"#
      #expect(form.canSubmit(action))
    }

    @Test func detachRequiresAttachmentName() throws {
      let action = try Self.action("pdf-detach")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      form.values["name"] = ""
      #expect(!form.canSubmit(action))
      form.values["name"] = "attachment.xml"
      #expect(form.canSubmit(action))
    }

    @Test func splitIntervalsAndPagesValidateInputs() throws {
      let action = try Self.action("pdf-split")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      form.values["splitMode"] = "intervals"
      form.values["every"] = "0"
      #expect(!form.canSubmit(action))
      form.values["every"] = "abc"
      #expect(!form.canSubmit(action))
      form.values["every"] = "2"
      #expect(form.canSubmit(action))

      form.values["splitMode"] = "pages"
      form.values["ranges"] = ""
      #expect(!form.canSubmit(action))
      form.values["ranges"] = "   ,  "
      #expect(!form.canSubmit(action))
      form.values["ranges"] = "1-2,4"
      #expect(form.canSubmit(action))
    }

    @Test func multilineFieldsRejectInvalidJSON() throws {
      let action = try Self.action("pdf-set-form")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      form.values["fields"] = #"{"agree":"#
      #expect(!form.canSubmit(action))
      form.values["fields"] = #"{"agree":"Yes"}"#
      #expect(form.canSubmit(action))
    }

    @Test func facturXGatesXMLAndRelatedFields() throws {
      let action = try Self.action("pdf-remediate")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]
      form.values["profile"] = "PDF/A-2b"
      form.values["level"] = "EN 16931"
      form.values["documentType"] = "INVOICE"
      let xml = try workspace.write("invoice.xml", contents: "<Invoice/>")
      form.extraFiles["xml"] = [xml]

      #expect(form.canSubmit(action))
      #expect(form.extraSlots(for: action).allSatisfy { $0.field != "xml" })
      let pdfaFields = form.fieldsToSend(action)
      #expect(pdfaFields.firstValue(for: "level") == nil)
      #expect(pdfaFields.firstValue(for: "documentType") == nil)
      #expect(pdfaFields.firstValue(for: "xml") == nil)

      form.values["profile"] = "Factur-X"
      form.extraFiles["xml"] = []
      #expect(!form.canSubmit(action))
      #expect(form.extraSlots(for: action).contains { $0.field == "xml" })

      form.extraFiles["xml"] = [xml]
      #expect(form.canSubmit(action))
      let facturFields = form.fieldsToSend(action)
      #expect(facturFields.firstValue(for: "level") == "EN 16931")
      #expect(facturFields.firstValue(for: "documentType") == "INVOICE")
      #expect(facturFields.firstValue(for: "xml") == "invoice.xml")
    }

    @Test func sendDefaultOmitsUnchangedOptionalFields() throws {
      let action = try Self.action("chromium-url-pdf")
      var form = ActionForm(action: action)
      form.url = "https://example.com"
      let fields = form.fieldsToSend(action)

      #expect(fields.firstValue(for: "url") == "https://example.com")
      #expect(fields.firstValue(for: "landscape") == nil)
      #expect(fields.firstValue(for: "printBackground") == nil)
      #expect(fields.firstValue(for: "scale") == nil)

      form.values["landscape"] = "true"
      form.values["scale"] = "1.25"
      let changed = form.fieldsToSend(action)
      #expect(changed.firstValue(for: "landscape") == "true")
      #expect(changed.firstValue(for: "scale") == "1.25")
      #expect(changed.firstValue(for: "printBackground") == nil)
    }

    @Test func sendDefaultKeepsRequiredRotateAngle() throws {
      let action = try Self.action("pdf-rotate")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: action)
      form.files = [try workspace.write("input.pdf")]

      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "angle") == "90")
    }

    @Test func paperSizePresetWritesWidthAndHeight() throws {
      let action = try Self.action("chromium-url-pdf")
      var form = ActionForm(action: action)
      form.url = "https://example.com"

      #expect(form.selectedPreset(FieldPresets.paperSize) == "letter")
      form.setPreset(FieldPresets.paperSize, id: "a4")
      #expect(form.selectedPreset(FieldPresets.paperSize) == "a4")
      #expect(form.values["paperWidth"] == "8.27")
      #expect(form.values["paperHeight"] == "11.7")

      let fields = form.fieldsToSend(action)
      #expect(fields.firstValue(for: "paperWidth") == "8.27")
      #expect(fields.firstValue(for: "paperHeight") == "11.7")
    }

    @Test func fileSlotsRejectWrongExtensionAndUnderCount() throws {
      let merge = try Self.action("pdf-merge")
      let workspace = try FixtureWorkspace()
      defer { workspace.cleanup() }
      var form = ActionForm(action: merge)
      let pdf = try workspace.write("input.pdf")
      let note = try workspace.write("note.txt", contents: "note")

      form.files = [pdf]
      #expect(!form.canSubmit(merge))
      form.files = [pdf, try workspace.write("second.pdf")]
      #expect(form.canSubmit(merge))
      form.files = [pdf, note]
      #expect(!form.canSubmit(merge))

      let sign = try Self.action("pdf-sign")
      var signForm = ActionForm(action: sign)
      signForm.files = [pdf]
      signForm.extraFiles["certificate"] = [note]
      #expect(!signForm.canSubmit(sign))
      signForm.extraFiles["certificate"] = [try workspace.write("cert.p12")]
      #expect(signForm.canSubmit(sign))

      let attach = try Self.action("pdf-attach")
      var attachForm = ActionForm(action: attach)
      attachForm.files = [pdf]
      #expect(!attachForm.canSubmit(attach))
      attachForm.extraFiles["attachments"] = [note]
      #expect(attachForm.canSubmit(attach))
    }
  }

  private final class FixtureWorkspace: @unchecked Sendable {
    let root: URL

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "thistle-form-\(UUID().uuidString)", isDirectory: true)
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
  }
#endif
