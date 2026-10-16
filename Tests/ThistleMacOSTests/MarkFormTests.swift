#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  @MainActor
  struct MarkFormTests {
    @Test func mixedMarksKeepFieldsAndFilesInOrder() throws {
      let action = try #require(ConvertAction.all.first { $0.id == "pdf-stamp" })
      var form = ActionForm(action: action)
      form.files = [URL(fileURLWithPath: "/tmp/input.pdf")]
      var image = PDFMark(text: "")
      image.source = .image
      image.files = [URL(fileURLWithPath: "/tmp/logo.png")]
      var pdf = PDFMark(text: "")
      pdf.source = .pdf
      pdf.files = [URL(fileURLWithPath: "/tmp/overlay.pdf")]
      form.marks = [PDFMark(text: "DRAFT"), image, PDFMark(text: "LAST"), pdf]
      let fields = form.fieldsToSend(action)
      #expect(
        fields.filter { $0.name == "stampSource" }.map(\.value) == ["text", "image", "text", "pdf"])
      #expect(
        fields.filter { $0.name == "stampExpression" }.map(\.value) == ["DRAFT", "", "LAST", ""])
      #expect(fields.filter { $0.name == "stampPages" }.map(\.value) == ["", "", "", ""])
      #expect(
        form.filesToSend(action).map(\.url.lastPathComponent) == [
          "input.pdf", "logo.png", "overlay.pdf",
        ])
      form.marks.swapAt(0, 3)
      #expect(
        form.fieldsToSend(action).filter { $0.name == "stampSource" }.map(\.value) == [
          "pdf", "image", "text", "text",
        ])
      #expect(
        form.filesToSend(action).map(\.url.lastPathComponent) == [
          "input.pdf", "overlay.pdf", "logo.png",
        ])
    }

    @Test func invalidMarkPreventsSubmission() throws {
      let action = try #require(ConvertAction.all.first { $0.id == "pdf-watermark" })
      var form = ActionForm(action: action)
      form.files = [URL(fileURLWithPath: "/tmp/input.pdf")]
      #expect(form.canSubmit(action))
      form.marks.append(PDFMark())
      #expect(!form.canSubmit(action))
      form.marks[1].text = "DRAFT"
      form.marks[1].options = #"{"opacity":0.5}"#
      #expect(!form.canSubmit(action))
      form.marks[1].options = #"{"op":"0.5"}"#
      #expect(form.canSubmit(action))
      form.marks[1].source = .image
      #expect(!form.canSubmit(action))
    }

    @Test func stagingAllowsReusingOneMarkFile() throws {
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
        files: [("files", source), ("stamp", source), ("stamp", source)])
      #expect(refs.map(\.field) == ["files", "stamp", "stamp"])
      #expect(Set(refs.map(\.filename)).count == 3)
      #expect(Set(refs.map(\.path)).count == 3)
      for ref in refs { #expect(try Data(contentsOf: ref.fileURL) == Data("test".utf8)) }
    }
  }
#endif
