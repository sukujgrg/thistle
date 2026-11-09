#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  @MainActor
  struct MarkFormTests {
    @Test func mixedStampsEncodeOrderedStagesAndFiles() throws {
      let action = try #require(ConvertAction.all.first { $0.id == "pdf-stamp" })
      var form = ActionForm(action: action)
      form.files = [URL(fileURLWithPath: "/tmp/input.pdf")]
      var image = PDFStamp(text: "")
      image.kind = .image
      image.files = [URL(fileURLWithPath: "/tmp/logo.png")]
      var pdf = PDFStamp(text: "")
      pdf.kind = .pdf
      pdf.files = [URL(fileURLWithPath: "/tmp/overlay.pdf")]
      form.stamps = [PDFStamp(text: "DRAFT"), image, PDFStamp(text: "LAST"), pdf]

      let fields = form.fieldsToSend(action)
      let stages = try #require(fields.firstValue(for: "stages"))
      #expect(stages.contains(#""op":"stamp-text""#))
      #expect(stages.contains(#""op":"stamp-image""#))
      #expect(stages.contains(#""op":"stamp-pdf""#))
      #expect(stages.contains("DRAFT"))
      #expect(stages.contains("LAST"))

      let uploads = form.filesToSend(action)
      #expect(uploads.map(\.field) == ["files", "files", "files"])
      #expect(uploads.map(\.filename) == [nil, "stamp-1.png", "stamp-3.pdf"])
      #expect(uploads.map(\.url.lastPathComponent) == ["input.pdf", "logo.png", "overlay.pdf"])
    }

    @Test func invalidStampPreventsSubmission() throws {
      let action = try #require(ConvertAction.all.first { $0.id == "pdf-stamp" })
      var form = ActionForm(action: action)
      form.files = [URL(fileURLWithPath: "/tmp/input.pdf")]
      #expect(form.canSubmit(action))
      form.stamps.append(PDFStamp(text: ""))
      #expect(!form.canSubmit(action))
      form.stamps[1].text = "DRAFT"
      #expect(form.canSubmit(action))
      form.stamps[1].kind = .image
      #expect(!form.canSubmit(action))
    }

    @Test func finishingBecomesStagesOnConvert() throws {
      let action = try #require(ConvertAction.all.first { $0.id == "chromium-html-pdf" })
      var form = ActionForm(action: action)
      form.files = [URL(fileURLWithPath: "/tmp/index.html")]
      form.finishing.merge = true
      form.finishing.remediate.profiles = ["PDF/A-2b"]
      form.finishing.encrypt.userPassword = "secret"
      let stages = try #require(form.fieldsToSend(action).firstValue(for: "stages"))
      #expect(stages.contains(#""op":"merge""#))
      #expect(stages.contains(#""op":"remediate""#))
      #expect(stages.contains(#""op":"encrypt""#))
      #expect(!form.fieldsToSend(action).contains { $0.name == "pdfa" })
    }

    @Test func stagingUsesOverrideFilenamesForStampAssets() throws {
      let action = try #require(ConvertAction.all.first { $0.id == "pdf-stamp" })
      let jobID = "mark-test-\(UUID().uuidString)"
      let source = FileManager.default.temporaryDirectory.appendingPathComponent(
        "mark-\(UUID().uuidString).pdf")
      try Data("test".utf8).write(to: source)
      defer {
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: Paths.jobDirectory(jobID))
      }
      let refs = try EngineController.stageFiles(
        jobID: jobID, action: action, fields: [],
        files: [
          FormFileUpload(field: "files", url: source),
          FormFileUpload(field: "files", url: source, filename: "stamp-0.pdf"),
          FormFileUpload(field: "files", url: source, filename: "stamp-1.pdf"),
        ])
      #expect(refs.map(\.field) == ["files", "files", "files"])
      #expect(refs.map(\.filename) == [
        source.lastPathComponent, "stamp-0.pdf", "stamp-1.pdf",
      ])
      for ref in refs { #expect(try Data(contentsOf: ref.fileURL) == Data("test".utf8)) }
    }
  }
#endif
