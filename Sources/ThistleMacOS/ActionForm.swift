#if os(macOS) && arch(arm64)

  import Foundation
  import SwiftUI

  import ThistleSupport

  struct ActionForm {
    var url: String = "https://example.com"
    var files: [URL] = []
    var extraFiles: [String: [URL]] = [:]
    var values: [String: String] = [:]
    var stamps: [PDFStamp] = []
    var finishing: ConversionFinishing = .init()

    init(action: ConvertAction) {
      for field in action.fields {
        values[field.key] = field.defaultValue
      }
      if action.composer == .stamps {
        stamps = [PDFStamp(text: "APPROVED")]
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
      if action.id == "pdf-remediate" || action.id == "pdf-validate" {
        if trimmed("profile").isEmpty {
          return false
        }
      }
      if action.id == "pdf-remediate", trimmed("profile") == "Factur-X" {
        if (extraFiles["xml"] ?? []).isEmpty {
          return false
        }
      }
      if action.id == "pdf-metadata-write" {
        let keys = ["title", "author", "subject", "keywords", "creator", "producer", "creationDate", "modDate"]
        if !keys.contains(where: { !trimmed($0).isEmpty }) {
          return false
        }
      }
      if action.id == "pdf-bookmarks-write", !hasNonEmptyJSONBookmarks("bookmarks") {
        return false
      }
      if action.id == "pdf-sign" {
        if (extraFiles["certificate"] ?? []).isEmpty {
          return false
        }
      }
      if action.id == "pdf-timestamp", trimmed("url").isEmpty {
        return false
      }
      if action.id == "pdf-detach", trimmed("name").isEmpty {
        return false
      }
      if action.id == "pdf-insert" {
        if (extraFiles["insert"] ?? []).isEmpty {
          return false
        }
      }
      if action.id == "pdf-split" {
        let mode = trimmed("splitMode")
        if mode == "intervals" {
          guard let every = Int(trimmed("every")), every > 0 else { return false }
        } else if mode == "pages" {
          if splitRanges(from: trimmed("ranges")).isEmpty {
            return false
          }
        }
      }
      for field in action.fields {
        if case .multiline = field.kind, !trimmed(field.key).isEmpty,
          jsonObject(field.key) == nil
        {
          return false
        }
      }
      if action.composer == .stamps {
        if stamps.isEmpty || stamps.contains(where: { $0.validationMessage != nil }) {
          return false
        }
      }
      if action.composer == .finishing, finishing.validationMessage != nil {
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
      var slots = action.extraFiles
      if action.id == "pdf-remediate", trimmed("profile") != "Factur-X" {
        slots = slots.filter { $0.field != "xml" }
      }
      return slots
    }

    func fieldsToSend(_ action: ConvertAction) -> [MultipartField] {
      switch action.composer {
      case .stamps:
        return encodeStages(stampStages(for: action))
      case .finishing:
        var out = baseFields(for: action)
        out += encodeStages(finishing.stages)
        return out
      case .fields:
        var out = baseFields(for: action)
        if action.id == "pdf-attach" {
          out += encodeStages(attachStages())
        }
        if action.id == "pdf-encrypt" {
          out += encryptPermissionFields()
        }
        if action.id == "pdf-split" {
          out = out.filter { $0.name != "every" && $0.name != "ranges" && $0.name != "splitMode" }
          out += splitFields()
        }
        return out
      }
    }

    private func baseFields(for action: ConvertAction) -> [MultipartField] {
      var out: [MultipartField] = []
      if action.urlField {
        out.append(MultipartField("url", url.trimmingCharacters(in: .whitespacesAndNewlines)))
      }
      for field in action.fields {
        if action.id == "pdf-split", field.key == "every", trimmed("splitMode") != "intervals" {
          continue
        }
        if action.id == "pdf-split", field.key == "ranges", trimmed("splitMode") != "pages" {
          continue
        }
        if action.id == "pdf-encrypt", encryptPermissionKeys.contains(field.key) {
          continue
        }
        let value = values[field.key] ?? field.defaultValue
        if !field.sendDefault, value == field.defaultValue {
          continue
        }
        switch field.kind {
        case .toggle:
          out.append(MultipartField(field.key, value))
        case .picker:
          if !value.isEmpty {
            out.append(MultipartField(field.key, value))
          }
        case .text, .secure, .multiline:
          let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
            out.append(MultipartField(field.key, trimmed))
          }
        }
      }
      if action.id == "pdf-remediate" {
        out = out.filter { field in
          if field.name == "level" || field.name == "documentType" {
            return trimmed("profile") == "Factur-X"
          }
          return true
        }
        if trimmed("profile") == "Factur-X", let xml = extraFiles["xml"]?.first {
          out.append(MultipartField("xml", xml.lastPathComponent))
        }
      }
      if action.id == "pdf-sign", let cert = extraFiles["certificate"]?.first {
        out.append(MultipartField("certificate", cert.lastPathComponent))
        if let key = extraFiles["key"]?.first {
          out.append(MultipartField("key", key.lastPathComponent))
        }
      }
      if action.id == "pdf-insert", let insert = extraFiles["insert"]?.first {
        out.append(MultipartField("source", insert.lastPathComponent))
      }
      return out
    }

    private let encryptPermissionKeys: Set<String> = [
      "print", "printHighQuality", "modifyContent", "extractText", "modifyAnnotations", "fillForms",
      "assemble",
    ]

    private func encryptPermissionFields() -> [MultipartField] {
      var options = EncryptOptions()
      options.userPassword = trimmed("userPassword")
      options.ownerPassword = trimmed("ownerPassword")
      options.algorithm = trimmed("algorithm").isEmpty ? "aes256" : trimmed("algorithm")
      options.print = values["print"] != "false"
      options.printHighQuality = values["printHighQuality"] != "false"
      options.modifyContent = values["modifyContent"] != "false"
      options.extractText = values["extractText"] != "false"
      options.modifyAnnotations = values["modifyAnnotations"] != "false"
      options.fillForms = values["fillForms"] != "false"
      options.assemble = values["assemble"] != "false"
      guard let permissions = options.jsonObject()["permissions"],
        JSONSerialization.isValidJSONObject(permissions)
      else { return [] }
      guard let json = try? JSONSerialization.data(withJSONObject: permissions, options: [.sortedKeys]),
        let text = String(data: json, encoding: .utf8)
      else { return [] }
      return [MultipartField("permissions", text)]
    }

    private func splitFields() -> [MultipartField] {
      let mode = trimmed("splitMode")
      if mode == "intervals", let every = Int(trimmed("every")), every > 0 {
        return [MultipartField("every", String(every))]
      }
      if mode == "pages" {
        let ranges = splitRanges(from: trimmed("ranges"))
        guard !ranges.isEmpty else { return [] }
        guard let data = try? JSONSerialization.data(withJSONObject: ranges, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
        else { return [] }
        return [MultipartField("ranges", text)]
      }
      return []
    }

    private func splitRanges(from raw: String) -> [String] {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return [] }
      if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
        let array = try? JSONSerialization.jsonObject(with: data) as? [String]
      {
        return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      }
      return
        trimmed
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func stampStages(for action: ConvertAction) -> [GotenbergStage] {
      stamps.enumerated().map { index, stamp in
        stamp.stage(assetFilename: stamp.assetFilename(index: index))
      }
    }

    private func attachStages() -> [GotenbergStage] {
      (extraFiles["attachments"] ?? []).map { .attach(file: $0.lastPathComponent) }
    }

    private func encodeStages(_ stages: [GotenbergStage]) -> [MultipartField] {
      guard !stages.isEmpty, let json = try? GotenbergStage.encodeJSON(stages) else { return [] }
      return [MultipartField("stages", json)]
    }

    func filesToSend(_ action: ConvertAction) -> [FormFileUpload] {
      var pairs: [FormFileUpload] = []
      if action.files != nil {
        for file in files {
          pairs.append(FormFileUpload(field: "files", url: file))
        }
      }
      for slot in extraSlots(for: action) {
        for file in extraFiles[slot.field] ?? [] {
          // Gotenberg 9 names assets from the `files` upload by filename.
          let underFiles = ["attachments", "certificate", "key", "xml", "insert"]
            .contains(slot.field)
          pairs.append(FormFileUpload(field: underFiles ? "files" : slot.field, url: file))
        }
      }
      if action.composer == .stamps {
        for (index, stamp) in stamps.enumerated() {
          guard stamp.kind != .text, let asset = stamp.assetFilename(index: index),
            let file = stamp.files.first
          else { continue }
          pairs.append(FormFileUpload(field: "files", url: file, filename: asset))
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
