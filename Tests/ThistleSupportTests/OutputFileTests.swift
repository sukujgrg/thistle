import Foundation
import Testing

@testable import ThistleSupport

struct OutputFileTests {
  @Test func filenameAddsExtensionOnce() {
    #expect(OutputFile.filename(basename: "report", ext: "pdf") == "report.pdf")
    #expect(OutputFile.filename(basename: "report.PDF", ext: "pdf") == "report.PDF")
    #expect(OutputFile.filename(basename: "  ", ext: "pdf") == "output.pdf")
  }

  @Test func suggestedBasenameSuffixesWhenOutputMatchesInput() {
    #expect(
      OutputFile.suggestedBasename(
        fromInputBasename: "invoice",
        inputExtension: "pdf",
        outputExtension: "pdf",
        defaultFilename: "optimized"
      ) == "invoice-optimized")
    #expect(
      OutputFile.suggestedBasename(
        fromInputBasename: "invoice-encrypted",
        inputExtension: "pdf",
        outputExtension: "pdf",
        defaultFilename: "encrypted"
      ) == "invoice-encrypted")
  }

  @Test func suggestedBasenameKeepsNameWhenTypeChanges() {
    #expect(
      OutputFile.suggestedBasename(
        fromInputBasename: "slides",
        inputExtension: "docx",
        outputExtension: "pdf",
        defaultFilename: "office"
      ) == "slides")
  }

  @Test func suggestedBasenameUsesDefaultWithoutInput() {
    #expect(
      OutputFile.suggestedBasename(
        fromInputBasename: nil,
        inputExtension: nil,
        outputExtension: "pdf",
        defaultFilename: "page"
      ) == "page")
  }

  @Test func suggestedBasenameSuffixesMergedFiles() {
    #expect(
      OutputFile.suggestedBasename(
        fromInputBasename: "a",
        inputExtension: "pdf",
        outputExtension: "pdf",
        defaultFilename: "merged"
      ) == "a-merged")
  }

  @Test func suggestedBasenameKeepsNameWhenInputExtensionIsMissing() {
    #expect(
      OutputFile.suggestedBasename(
        fromInputBasename: "index",
        inputExtension: nil,
        outputExtension: "pdf",
        defaultFilename: "document"
      ) == "index")
  }

  @Test func copyToSameURLLeavesFile() throws {
    let root = try scratch()
    let file = root.appendingPathComponent("saved.pdf")
    try Data("keep".utf8).write(to: file)
    try OutputFile.place(file, at: file, moving: false)
    #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == "keep")
  }

  @Test func saveACopyOverItselfDoesNotDeleteSource() throws {
    let root = try scratch()
    let file = root.appendingPathComponent("saved.pdf")
    try Data("keep".utf8).write(to: file)
    let alias = URL(fileURLWithPath: file.path(percentEncoded: false))
    try OutputFile.place(file, at: alias, moving: false)
    #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == "keep")
  }

  @Test func copyReplacesDestinationWithoutDeletingSourceFirst() throws {
    let root = try scratch()
    let source = root.appendingPathComponent("source.pdf")
    let dest = root.appendingPathComponent("dest.pdf")
    try Data("new".utf8).write(to: source)
    try Data("old".utf8).write(to: dest)
    try OutputFile.place(source, at: dest, moving: false)
    #expect(String(data: try Data(contentsOf: dest), encoding: .utf8) == "new")
    #expect(String(data: try Data(contentsOf: source), encoding: .utf8) == "new")
  }

  @Test func moveReplacesDestinationAtomically() throws {
    let root = try scratch()
    let source = root.appendingPathComponent("source.pdf")
    let dest = root.appendingPathComponent("dest.pdf")
    try Data("new".utf8).write(to: source)
    try Data("old".utf8).write(to: dest)
    try OutputFile.place(source, at: dest, moving: true)
    #expect(String(data: try Data(contentsOf: dest), encoding: .utf8) == "new")
    #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
  }

  @Test func moveToMissingDestinationRenamesSource() throws {
    let root = try scratch()
    let source = root.appendingPathComponent("source.pdf")
    let dest = root.appendingPathComponent("dest.pdf")
    try Data("payload".utf8).write(to: source)
    try OutputFile.place(source, at: dest, moving: true)
    #expect(String(data: try Data(contentsOf: dest), encoding: .utf8) == "payload")
    #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
  }

  @Test func copyToMissingDestinationLeavesSource() throws {
    let root = try scratch()
    let source = root.appendingPathComponent("source.pdf")
    let dest = root.appendingPathComponent("dest.pdf")
    try Data("payload".utf8).write(to: source)
    try OutputFile.place(source, at: dest, moving: false)
    #expect(String(data: try Data(contentsOf: dest), encoding: .utf8) == "payload")
    #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
  }

  @Test func clearDirectoryKeepsSelectedChild() throws {
    let root = try scratch()
    let keep = root.appendingPathComponent("keep")
    let drop = root.appendingPathComponent("drop")
    try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: keep.appendingPathComponent("file.pdf"))
    OutputFile.clearDirectory(root, keeping: keep)
    #expect(FileManager.default.fileExists(atPath: keep.path(percentEncoded: false)))
    #expect(!FileManager.default.fileExists(atPath: drop.path(percentEncoded: false)))
  }

  private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "thistle-output-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
