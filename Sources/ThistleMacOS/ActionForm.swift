#if os(macOS) && arch(arm64)

  import Foundation
  import SwiftUI

  import ThistleSupport

  struct ActionForm {
    var url: String = "https://example.com"
    var files: [URL] = []
    var extraFiles: [String: [URL]] = [:]
    var values: [String: String] = [:]

    init(action: ConvertAction) {
      for field in action.fields {
        values[field.key] = field.defaultValue
      }
    }

    func selectedPreset(_ group: PresetGroup) -> String {
      if let stored = values[Self.presetStorageKey(group.id)] {
        return stored
      }
      return group.matching(values)
    }

    mutating func setPreset(_ group: PresetGroup, id: String) {
      values[Self.presetStorageKey(group.id)] = id
      group.apply(id, to: &values)
    }

    private static func presetStorageKey(_ groupID: String) -> String {
      "preset.\(groupID)"
    }

    func canSubmit(_ action: ConvertAction) -> Bool {
      if action.urlField {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() else {
          return false
        }
        guard scheme == "http" || scheme == "https", parsed.host != nil else {
          return false
        }
      }
      if let slot = action.files {
        if slot.required, files.count < slot.minimumCount {
          return false
        }
        if slot.rejection(for: files) != nil {
          return false
        }
      }
      for slot in extraSlots(for: action) {
        let selected = extraFiles[slot.field] ?? []
        if slot.required, selected.count < slot.minimumCount {
          return false
        }
        if slot.rejection(for: selected) != nil {
          return false
        }
      }
      if action.id == "pdf-encrypt" {
        if trimmed("userPassword").isEmpty && trimmed("ownerPassword").isEmpty {
          return false
        }
      }
      if action.id == "pdf-convert" {
        let pdfuaOn = values["pdfua"] == "true"
        if trimmed("pdfa").isEmpty && !pdfuaOn {
          return false
        }
      }
      if action.id == "pdf-metadata-write", !hasNonEmptyJSONObject("metadata") {
        return false
      }
      if action.id == "pdf-bookmarks-write", !hasNonEmptyJSONBookmarks("bookmarks") {
        return false
      }
      for field in action.fields {
        if case .multiline = field.kind, !trimmed(field.key).isEmpty,
          jsonObject(field.key) == nil
        {
          return false
        }
      }
      let splitMode = trimmed("splitMode")
      if !splitMode.isEmpty && trimmed("splitSpan").isEmpty {
        return false
      }
      if values["splitUnify"] == "true" {
        if splitMode != "pages" {
          return false
        }
      }
      if !markSourceIsValid(prefix: "watermark", fileField: "watermark") {
        return false
      }
      if !markSourceIsValid(prefix: "stamp", fileField: "stamp") {
        return false
      }
      return true
    }

    private func trimmed(_ key: String) -> String {
      (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func jsonObject(_ key: String) -> Any? {
      let raw = trimmed(key)
      guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
      return try? JSONSerialization.jsonObject(with: data)
    }

    private func hasNonEmptyJSONObject(_ key: String) -> Bool {
      guard let object = jsonObject(key) as? [String: Any] else { return false }
      return !object.isEmpty
    }

    private func hasNonEmptyJSONBookmarks(_ key: String) -> Bool {
      guard let object = jsonObject(key) else { return false }
      if let list = object as? [Any] {
        return !list.isEmpty
      }
      if let map = object as? [String: Any] {
        return !map.isEmpty
      }
      return false
    }

    func extraSlots(for action: ConvertAction) -> [FileSlot] {
      action.extraFiles.compactMap { slot in
        switch slot.field {
        case "watermark", "stamp":
          switch trimmed("\(slot.field)Source") {
          case "image":
            return slot.refined(
              types: ConvertUTType.images,
              extensions: ConvertUTType.imageExtensions,
              help: "PNG, JPEG, or WebP.")
          case "pdf":
            return slot.refined(
              types: ConvertUTType.pdf,
              extensions: ConvertUTType.pdfExtensions,
              help: "One PDF used as the mark.")
          default:
            return nil
          }
        default:
          return slot
        }
      }
    }

    private func hasExtra(_ field: String) -> Bool {
      !(extraFiles[field] ?? []).isEmpty
    }

    private func markGroupActive(prefix: String, fileField: String) -> Bool {
      if !trimmed("\(prefix)Expression").isEmpty {
        return true
      }
      if hasExtra(fileField) {
        return true
      }
      let source = trimmed("\(prefix)Source")
      return source == "text" || source == "image" || source == "pdf"
    }

    private func markSourceIsValid(prefix: String, fileField: String) -> Bool {
      if !markGroupActive(prefix: prefix, fileField: fileField) {
        return true
      }
      let source = trimmed("\(prefix)Source")
      if source == "image" || source == "pdf" {
        return hasExtra(fileField)
      }
      return !trimmed("\(prefix)Expression").isEmpty
    }

    func fieldsToSend(_ action: ConvertAction) -> [String: String] {
      var out: [String: String] = [:]
      if action.urlField {
        out["url"] = url.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      for field in action.fields {
        if shouldSkipMarkField(field) {
          continue
        }
        if shouldSkipSplitField(field) {
          continue
        }
        if shouldSkipEncryptField(field, action: action) {
          continue
        }
        if shouldSkipFacturxField(field) {
          continue
        }
        if field.key == "embedsMetadata", !hasExtra("embeds") {
          continue
        }
        if shouldSkipRotateField(field, action: action) {
          continue
        }
        if shouldSkipNativeWatermarkField(field) {
          continue
        }
        let value = values[field.key] ?? field.defaultValue
        if !field.sendDefault, value == field.defaultValue {
          continue
        }
        switch field.kind {
        case .toggle:
          out[field.key] = value
        case .picker:
          if !value.isEmpty {
            out[field.key] = value
          }
        case .text, .secure, .multiline:
          let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            out[field.key] = trimmed
          }
        }
      }
      return out
    }

    func filesToSend(_ action: ConvertAction) -> [(field: String, url: URL)] {
      var pairs: [(field: String, url: URL)] = []
      if action.files != nil {
        for file in files {
          pairs.append((field: "files", url: file))
        }
      }
      for slot in action.extraFiles {
        if shouldSkipMarkFile(slot) {
          continue
        }
        for file in extraFiles[slot.field] ?? [] {
          pairs.append((field: slot.field, url: file))
        }
      }
      return pairs
    }

    func suggestedOutputName(for action: ConvertAction) -> String {
      let fromFiles = Self.basename(fromFiles: files, action: action)
      let fromURL = action.urlField ? Self.basename(fromURL: url) : nil
      return OutputFile.suggestedBasename(
        fromInputBasename: fromFiles ?? fromURL,
        inputExtension: Self.sharedPathExtension(files),
        outputExtension: action.outputExtension,
        defaultFilename: action.defaultFilename
      )
    }

    func suggestedSaveDirectory() -> URL? {
      guard let file = files.first else { return nil }
      let directory = file.deletingLastPathComponent()
      var isDirectory: ObjCBool = false
      guard
        FileManager.default.fileExists(
          atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        return nil
      }
      return directory
    }

    private static func sharedPathExtension(_ files: [URL]) -> String? {
      guard let first = files.first?.pathExtension, !first.isEmpty else { return nil }
      let ext = first.lowercased()
      guard files.allSatisfy({ $0.pathExtension.lowercased() == ext }) else { return nil }
      return first
    }

    private static func basename(fromFiles files: [URL], action: ConvertAction) -> String? {
      guard !files.isEmpty else { return nil }
      if files.count == 1 {
        return sanitize(files[0].deletingPathExtension().lastPathComponent)
      }

      let markdown = files.first { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
      if action.id.contains("markdown"), let markdown {
        return sanitize(markdown.deletingPathExtension().lastPathComponent)
      }

      if action.id.contains("html") || action.id.contains("markdown") {
        let html =
          files.first { $0.lastPathComponent.lowercased() == "index.html" }
          ?? files.first { ["html", "htm"].contains($0.pathExtension.lowercased()) }
        if let html {
          return sanitize(html.deletingPathExtension().lastPathComponent)
        }
      }

      return sanitize(files[0].deletingPathExtension().lastPathComponent)
    }

    private static func basename(fromURL string: String) -> String? {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: trimmed) else { return nil }
      let pathPart = url.path.split(separator: "/").last.map(String.init) ?? ""
      if !pathPart.isEmpty, pathPart != "/" {
        if let name = sanitize(
          URL(fileURLWithPath: pathPart).deletingPathExtension().lastPathComponent)
        {
          return name
        }
      }
      return sanitize(url.host ?? "")
    }

    private static func sanitize(_ raw: String) -> String? {
      var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      for invalid in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"] {
        name = name.replacingOccurrences(of: invalid, with: "-")
      }
      name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
      guard !name.isEmpty, name != "." else { return nil }
      return name
    }

    private func shouldSkipSplitField(_ field: FormField) -> Bool {
      let splitKeys: Set<String> = ["splitSpan", "splitUnify"]
      guard splitKeys.contains(field.key) else { return false }
      return trimmed("splitMode").isEmpty
    }

    private func shouldSkipEncryptField(_ field: FormField, action: ConvertAction) -> Bool {
      let keys: Set<String> = [
        "userPassword", "ownerPassword", "allowPrinting", "allowCopying", "allowModifying",
        "allowAnnotating", "allowFillingForms", "allowAssembling",
      ]
      guard keys.contains(field.key) else { return false }
      if action.id == "pdf-encrypt" {
        return false
      }
      return trimmed("userPassword").isEmpty && trimmed("ownerPassword").isEmpty
    }

    private func shouldSkipFacturxField(_ field: FormField) -> Bool {
      guard field.key.hasPrefix("facturx") else { return false }
      if hasExtra("facturxXml") {
        return false
      }
      return trimmed("facturxConformanceLevel").isEmpty
        && trimmed("facturxDocumentType").isEmpty
        && trimmed("facturxVersion").isEmpty
    }

    private func shouldSkipNativeWatermarkField(_ field: FormField) -> Bool {
      let keys: Set<String> = [
        "nativeWatermarkText", "nativeTiledWatermarkText", "nativeWatermarkColor",
        "nativeWatermarkFontHeight", "nativeWatermarkRotateAngle", "nativeWatermarkFontName",
      ]
      guard keys.contains(field.key) else { return false }
      return trimmed("nativeWatermarkText").isEmpty && trimmed("nativeTiledWatermarkText").isEmpty
    }

    private func shouldSkipRotateField(_ field: FormField, action: ConvertAction) -> Bool {
      guard field.key == "rotateAngle" || field.key == "rotatePages" else { return false }
      if action.id == "pdf-rotate" {
        return false
      }
      return trimmed("rotateAngle").isEmpty
    }

    private func shouldSkipMarkField(_ field: FormField) -> Bool {
      if field.key.hasPrefix("watermark") {
        if !markGroupActive(prefix: "watermark", fileField: "watermark") {
          return true
        }
        if field.key == "watermarkExpression" {
          return trimmed("watermarkSource") == "image" || trimmed("watermarkSource") == "pdf"
        }
      }
      if field.key.hasPrefix("stamp") {
        if !markGroupActive(prefix: "stamp", fileField: "stamp") {
          return true
        }
        if field.key == "stampExpression" {
          return trimmed("stampSource") == "image" || trimmed("stampSource") == "pdf"
        }
      }
      return false
    }

    private func shouldSkipMarkFile(_ slot: FileSlot) -> Bool {
      if slot.field == "watermark" {
        if !markGroupActive(prefix: "watermark", fileField: "watermark") {
          return true
        }
        return trimmed("watermarkSource") == "text"
      }
      if slot.field == "stamp" {
        if !markGroupActive(prefix: "stamp", fileField: "stamp") {
          return true
        }
        return trimmed("stampSource") == "text"
      }
      if slot.field == "facturxXml" {
        return !hasExtra("facturxXml")
          && trimmed("facturxConformanceLevel").isEmpty
          && trimmed("facturxDocumentType").isEmpty
          && trimmed("facturxVersion").isEmpty
      }
      return false
    }
  }

  extension Binding where Value == ActionForm {
    func value(for field: FormField) -> Binding<String> {
      Binding<String>(
        get: { wrappedValue.values[field.key] ?? field.defaultValue },
        set: { wrappedValue.values[field.key] = $0 }
      )
    }

    func toggle(for field: FormField) -> Binding<Bool> {
      Binding<Bool>(
        get: { (wrappedValue.values[field.key] ?? field.defaultValue) == "true" },
        set: { wrappedValue.values[field.key] = $0 ? "true" : "false" }
      )
    }

    func extraFiles(for slot: FileSlot) -> Binding<[URL]> {
      Binding<[URL]>(
        get: { wrappedValue.extraFiles[slot.field] ?? [] },
        set: { wrappedValue.extraFiles[slot.field] = $0 }
      )
    }

    func preset(_ group: PresetGroup) -> Binding<String> {
      Binding<String>(
        get: { wrappedValue.selectedPreset(group) },
        set: { wrappedValue.setPreset(group, id: $0) }
      )
    }
  }

#endif
