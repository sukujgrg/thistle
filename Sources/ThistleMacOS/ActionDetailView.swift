#if os(macOS) && arch(arm64)

  import AppKit
  import PDFKit
  import SwiftUI

  import ThistleSupport

  struct ActionDetailView: View {
    let action: ConvertAction
    @Environment(EngineController.self) private var controller
    @State private var form: ActionForm
    @State private var expandedSections: Set<String> = []
    @State private var importingSlot: FileSlot?
    @State private var filePicker: FileSlotPicker?
    @State private var importError: String?

    init(action: ConvertAction) {
      self.action = action
      _form = State(initialValue: ActionForm(action: action))
    }

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            header
            inputSection
            extraFilesSection
            optionsSection
            runSection
            resultSection
              .id("result")
          }
          .padding(28)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .onChange(of: showsResult) { _, shown in
          guard shown else { return }
          withAnimation(.snappy(duration: 0.22)) {
            proxy.scrollTo("result", anchor: .center)
          }
        }
      }
      .onChange(of: action.id) {
        form = ActionForm(action: action)
        expandedSections = []
        importError = nil
      }
    }

    private var showsResult: Bool {
      guard controller.resultActionID == action.id else { return false }
      if case .succeeded = controller.jobStatus { return true }
      if case .failed = controller.jobStatus { return true }
      return controller.jsonPreview != nil
    }

    private var header: some View {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: action.icon)
          .font(.title2)
          .foregroundStyle(.tint)
          .frame(width: 36, height: 36)
          .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 4) {
          Text(action.title)
            .font(.title2.weight(.semibold))
          Text(action.subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
          Text(action.path)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
      }
    }

    @ViewBuilder
    private var inputSection: some View {
      if let slot = action.files {
        FileWell(
          slot: slot,
          files: $form.files,
          enabled: !controller.isWorking
        ) {
          presentPicker(for: slot)
        }
      }
    }

    @ViewBuilder
    private var extraFilesSection: some View {
      ForEach(visibleExtraFiles, id: \.field) { slot in
        FileWell(
          slot: slot,
          files: $form.extraFiles(for: slot),
          enabled: !controller.isWorking
        ) {
          presentPicker(for: slot)
        }
      }
    }

    private var visibleExtraFiles: [FileSlot] {
      form.extraSlots(for: action)
    }

    private var optionSections: [(title: String, fields: [FormField])] {
      var order: [String] = []
      var grouped: [String: [FormField]] = [:]
      for field in action.fields {
        if grouped[field.section] == nil {
          order.append(field.section)
        }
        grouped[field.section, default: []].append(field)
      }
      return order.map { (title: $0, fields: grouped[$0] ?? []) }
    }

    private static let collapsibleSections: Set<String> = [
      "Wait", "Request", "Export", "Viewer", "Encryption", "Native watermark",
    ]

    // Encryption is optional on convert/merge/split. On Encrypt it is the job.
    private func isCollapsible(_ sectionTitle: String) -> Bool {
      if action.id == "pdf-encrypt", sectionTitle == "Encryption" {
        return false
      }
      return Self.collapsibleSections.contains(sectionTitle)
    }

    @ViewBuilder
    private var optionsSection: some View {
      if action.urlField || !action.fields.isEmpty {
        Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
          if action.urlField {
            GridRow {
              optionLabel("URL")
              controlColumn(
                help: "http or https URL Chromium opens.",
                showsCaption: false
              ) {
                TextField("URL", text: $form.url, prompt: Text("https://example.com"))
                  .labelsHidden()
                  .textFieldStyle(.roundedBorder)
              }
            }
          }
          ForEach(optionSections, id: \.title) { section in
            optionSection(section)
          }
        }
        .disabled(controller.isWorking)
        .animation(.snappy(duration: 0.2), value: expandedSections)
      }
    }

    @ViewBuilder
    private func optionSection(_ section: (title: String, fields: [FormField])) -> some View {
      let items = formItems(from: section.fields)
      let collapsible = isCollapsible(section.title)
      let showTitle = collapsible || optionSections.count > 1 || section.title != "Options"
      let expanded = !collapsible || expandedSections.contains(section.title)

      if showTitle {
        GridRow {
          sectionTitle(section.title, collapsible: collapsible)
            .gridCellColumns(2)
            .gridCellAnchor(.leading)
        }
      }
      if expanded {
        ForEach(items) { item in
          formItem(item)
        }
      }
    }

    private func sectionTitle(_ title: String, collapsible: Bool) -> some View {
      let expanded = expandedSections.contains(title)
      return Group {
        if collapsible {
          Button {
            withAnimation(.snappy(duration: 0.2)) {
              if expanded {
                expandedSections.remove(title)
              } else {
                expandedSections.insert(title)
              }
            }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
              Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
              Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(title)
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
          .accessibilityHint(expanded ? "Hides these options" : "Shows these options")
        } else {
          Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.top, 6)
    }

    private func optionLabel(_ text: String, help: String = "") -> some View {
      Text(text)
        .multilineTextAlignment(.trailing)
        .gridColumnAlignment(.trailing)
        .help(help)
    }

    private func controlColumn<Content: View>(
      help: String,
      showsCaption: Bool,
      @ViewBuilder content: () -> Content
    ) -> some View {
      VStack(alignment: .leading, spacing: 3) {
        content()
        if showsCaption, !help.isEmpty {
          Text(help)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .help(help)
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func formItem(_ item: FormItem) -> some View {
      switch item {
      case .field(let field):
        fieldRow(field)
      case .presets(let label, let fields, let group):
        presetRow(label: label, fields: fields, group: group)
      }
    }

    private func presetRow(label: String, fields: [FormField], group: PresetGroup) -> some View {
      let isCustom = form.selectedPreset(group) == FieldPreset.customID
      let help = fields.first?.help ?? ""
      let showsCaption = isCustom && (fields.first?.showsCaption ?? false)
      return GridRow(alignment: .top) {
        optionLabel(label, help: help)
        controlColumn(help: help, showsCaption: showsCaption) {
          VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $form.preset(group)) {
              ForEach(group.presets) { preset in
                Text(preset.title).tag(preset.id)
              }
              Divider()
              Text("Custom").tag(FieldPreset.customID)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCustom {
              customPresetFields(fields)
            }
          }
        }
      }
    }

    @ViewBuilder
    private func customPresetFields(_ fields: [FormField]) -> some View {
      if fields.count == 4 {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
          GridRow {
            compactField(fields[0], prompt: "Top")
            compactField(fields[1], prompt: "Bottom")
          }
          GridRow {
            compactField(fields[2], prompt: "Left")
            compactField(fields[3], prompt: "Right")
          }
        }
      } else if fields.count == 2 {
        HStack(spacing: 8) {
          compactField(fields[0], prompt: pairPrompt(fields[0], fallback: "Width"))
          compactField(fields[1], prompt: pairPrompt(fields[1], fallback: "Height"))
        }
      } else if let field = fields.first {
        switch field.kind {
        case .multiline:
          ZStack(alignment: .topLeading) {
            JSONTextEditor(text: $form.value(for: field))
              .frame(minHeight: 88)
              .padding(4)
              .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            if !field.placeholder.isEmpty, (form.values[field.key] ?? "").isEmpty {
              Text(field.placeholder)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .allowsHitTesting(false)
            }
          }
        default:
          TextField("", text: $form.value(for: field), prompt: Text(field.placeholder))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
        }
      }
    }

    private func compactField(_ field: FormField, prompt: String) -> some View {
      TextField(
        prompt,
        text: $form.value(for: field),
        prompt: Text(field.placeholder.isEmpty ? prompt : field.placeholder)
      )
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
    }

    private func pairPrompt(_ field: FormField, fallback: String) -> String {
      if field.key == "paperWidth" {
        return "Width (in)"
      }
      if field.key == "paperHeight" {
        return "Height (in)"
      }
      if field.key.lowercased().contains("width") {
        return "Width"
      }
      if field.key.lowercased().contains("height") {
        return "Height"
      }
      return fallback
    }

    private func formItems(from fields: [FormField]) -> [FormItem] {
      var items: [FormItem] = []
      var index = 0
      while index < fields.count {
        let field = fields[index]
        if field.key == "paperWidth", index + 1 < fields.count,
          fields[index + 1].key == "paperHeight"
        {
          items.append(
            .presets(
              label: "Paper size",
              fields: [field, fields[index + 1]],
              group: FieldPresets.paperSize))
          index += 2
          continue
        }
        if field.key == "marginTop", index + 3 < fields.count,
          fields[index + 1].key == "marginBottom",
          fields[index + 2].key == "marginLeft",
          fields[index + 3].key == "marginRight"
        {
          items.append(
            .presets(
              label: "Margins",
              fields: Array(fields[index...index + 3]),
              group: FieldPresets.margins))
          index += 4
          continue
        }
        if field.key == "width", index + 1 < fields.count, fields[index + 1].key == "height" {
          items.append(
            .presets(
              label: "Size",
              fields: [field, fields[index + 1]],
              group: FieldPresets.captureSize))
          index += 2
          continue
        }
        if let group = presetGroup(for: field) {
          items.append(.presets(label: field.label, fields: [field], group: group))
          index += 1
          continue
        }
        items.append(.field(field))
        index += 1
      }
      return items
    }

    private func presetGroup(for field: FormField) -> PresetGroup? {
      switch field.key {
      case "scale":
        FieldPresets.scale
      case "waitDelay":
        FieldPresets.waitDelay
      case "userAgent":
        FieldPresets.userAgent
      case "deviceScaleFactor":
        FieldPresets.deviceScale
      case "emulatedMediaFeatures":
        FieldPresets.colorScheme
      case "imageQuality":
        FieldPresets.quality(
          key: field.key, emptyTitle: field.defaultValue.isEmpty ? "Default" : nil)
      case "quality":
        FieldPresets.quality(
          key: field.key, emptyTitle: field.defaultValue.isEmpty ? "Default" : nil)
      default:
        nil
      }
    }

    @ViewBuilder
    private func fieldRow(_ field: FormField) -> some View {
      switch field.kind {
      case .text:
        GridRow {
          optionLabel(field.label, help: field.help)
          controlColumn(help: field.help, showsCaption: field.showsCaption) {
            TextField("", text: $form.value(for: field), prompt: Text(field.placeholder))
              .labelsHidden()
              .textFieldStyle(.roundedBorder)
          }
        }
      case .secure:
        GridRow {
          optionLabel(field.label, help: field.help)
          controlColumn(help: field.help, showsCaption: field.showsCaption) {
            SecureField("", text: $form.value(for: field), prompt: Text(field.placeholder))
              .labelsHidden()
              .textFieldStyle(.roundedBorder)
          }
        }
      case .toggle:
        GridRow {
          optionLabel(field.label, help: field.help)
          controlColumn(help: field.help, showsCaption: field.showsCaption) {
            Toggle("", isOn: $form.toggle(for: field))
              .labelsHidden()
              .toggleStyle(.checkbox)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      case .picker(let options):
        GridRow {
          optionLabel(field.label, help: field.help)
          controlColumn(help: field.help, showsCaption: field.showsCaption) {
            Picker("", selection: $form.value(for: field)) {
              ForEach(options, id: \.self) { option in
                Text(pickerOptionTitle(option, field: field)).tag(option)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      case .multiline:
        GridRow(alignment: .top) {
          optionLabel(field.label, help: field.help)
          controlColumn(help: field.help, showsCaption: field.showsCaption) {
            ZStack(alignment: .topLeading) {
              JSONTextEditor(text: $form.value(for: field))
                .frame(minHeight: 88)
                .padding(4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
              if !field.placeholder.isEmpty, (form.values[field.key] ?? "").isEmpty {
                Text(field.placeholder)
                  .font(.system(.caption, design: .monospaced))
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 10)
                  .allowsHitTesting(false)
              }
            }
          }
        }
      }
    }

    private func pickerOptionTitle(_ option: String, field: FormField) -> String {
      if option.isEmpty {
        return "None"
      }
      switch field.key {
      case "initialView":
        return [
          "0": "None",
          "1": "Outlines",
          "2": "Thumbnails",
        ][option] ?? option
      case "magnification":
        return [
          "0": "Default",
          "1": "Fit page",
          "2": "Fit width",
          "3": "Fit visible",
          "4": "Use zoom",
        ][option] ?? option
      case "pageLayout":
        return [
          "0": "Default",
          "1": "Single page",
          "2": "One column",
          "3": "Two columns",
        ][option] ?? option
      case "openBookmarkLevels":
        return option == "-1" ? "All" : option
      default:
        return option
      }
    }

    private var runSection: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Button {
            Task { await run() }
          } label: {
            if controller.isWorking {
              ProgressView()
                .controlSize(.small)
                .padding(.trailing, 4)
            }
            Text(controller.isWorking ? "Working…" : action.runTitle)
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!canRun)
          Spacer()
        }

        if let importError {
          Text(importError)
            .font(.callout)
            .foregroundStyle(.red)
        } else if controller.hasUnappliedRemoteURL {
          Text("Connect to apply the edited URL before running this action.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if controller.usesRemote && !controller.isRunning {
          Text("Connect to the custom Gotenberg URL before running this action.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if controller.usesRemote {
          Text("Requests go to the custom Gotenberg URL. The local VM is stopped.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if !controller.isRunning {
          Text(
            "Run starts the engine if it is stopped. Quitting the app leaves the engine running."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
    }

    @ViewBuilder
    private var resultSection: some View {
      if case .succeeded(let path) = controller.jobStatus, controller.resultActionID == action.id {
        ResultCard(path: path, saved: controller.resultSaved) {
          controller.openResult()
        } reveal: {
          controller.revealResult()
        } save: {
          Task { await controller.saveResult() }
        }
      }
      if let message = controller.saveError, controller.resultActionID == action.id {
        Text(message)
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
      if case .failed(let message) = controller.jobStatus, controller.resultActionID == action.id {
        Text(message)
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
      if let json = controller.jsonPreview, controller.resultActionID == action.id {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("JSON")
              .font(.headline)
            Spacer()
            Button("Save JSON…") {
              Task { await controller.saveJSONPreview(defaultName: action.defaultFilename) }
            }
            .buttonStyle(.borderless)
          }
          JSONTextEditor(text: .constant(json), isEditable: false)
            .frame(minHeight: 180)
            .padding(4)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }

    private var canRun: Bool {
      !controller.isWorking && controller.canSubmitJobs && form.canSubmit(action)
    }

    private func run() async {
      importError = nil
      await controller.submit(
        action: action,
        fields: form.fieldsToSend(action),
        files: form.filesToSend(action),
        suggestedName: form.suggestedOutputName(for: action),
        saveDirectory: form.suggestedSaveDirectory()
      )
    }

    private func presentPicker(for slot: FileSlot) {
      importError = nil
      importingSlot = slot
      let picker = FileSlotPicker(slot: slot) { result in
        if let result {
          handleImport(result)
        } else {
          importingSlot = nil
        }
        filePicker = nil
      }
      filePicker = picker
      picker.present()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
      defer { importingSlot = nil }
      switch result {
      case .failure(let error):
        importError = error.localizedDescription
      case .success(let urls):
        guard let slot = importingSlot else { return }
        let selected = slot.allowsMultiple ? urls : Array(urls.prefix(1))
        let accepted = slot.accepted(from: selected)
        if accepted.count != selected.count, let message = slot.rejection(for: selected) {
          importError = message
        }
        if slot.field == "files" {
          form.files =
            slot.allowsMultiple
            ? form.files + accepted.filter { !form.files.contains($0) } : accepted
        } else {
          form.extraFiles[slot.field] = accepted
        }
      }
    }
  }

  private struct ResultCard: View {
    let path: String
    let saved: Bool
    var open: () -> Void
    var reveal: () -> Void
    var save: () -> Void

    private var url: URL { URL(fileURLWithPath: path) }

    private var folderLabel: String {
      saved ? ByteFormat.path(url.deletingLastPathComponent()) : "Not saved yet"
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
              .font(.headline)
              .textSelection(.enabled)
              .lineLimit(1)
            Text(folderLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .lineLimit(1)
              .help(path)
          }
          Spacer(minLength: 8)
          HStack(spacing: 8) {
            if saved {
              Button("Open", action: open)
              Button("Show in Finder", action: reveal)
                .buttonStyle(.borderless)
              Button("Save a Copy…", action: save)
            } else {
              Button("Save As…", action: save)
                .buttonStyle(.borderedProminent)
              Button("Open", action: open)
              Button("Show in Finder", action: reveal)
                .buttonStyle(.borderless)
            }
          }
        }
        ResultPreview(url: url)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(.separator.opacity(0.6))
      )
    }
  }

  private struct ResultPreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
      Group {
        if let image {
          Button {
            NSWorkspace.shared.open(url)
          } label: {
            Image(nsImage: image)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 420)
              .frame(maxWidth: .infinity)
              .background(Color.white)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .strokeBorder(.separator.opacity(0.6))
              )
          }
          .buttonStyle(.plain)
          .help("Open")
        }
      }
      .task(id: url) {
        image = Self.thumbnail(for: url)
      }
    }

    private static func thumbnail(for url: URL) -> NSImage? {
      switch url.pathExtension.lowercased() {
      case "pdf":
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let maxWidth: CGFloat = 720
        let scale = min(2, maxWidth / max(bounds.width, 1))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
      case "png", "jpg", "jpeg", "webp":
        return NSImage(contentsOf: url)
      default:
        return nil
      }
    }
  }

  @MainActor
  final class FileSlotPicker: NSObject, NSOpenSavePanelDelegate {
    private let slot: FileSlot
    private let onPicked: (Result<[URL], Error>?) -> Void

    init(slot: FileSlot, onPicked: @escaping (Result<[URL], Error>?) -> Void) {
      self.slot = slot
      self.onPicked = onPicked
    }

    func present() {
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = slot.allowsMultiple
      panel.allowedContentTypes = slot.pickerTypes
      panel.delegate = self
      panel.begin { [weak self] response in
        guard let self else { return }
        if response == .OK {
          self.onPicked(.success(panel.urls))
        } else {
          self.onPicked(nil)
        }
      }
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        return true
      }
      return slot.accepts(url)
    }
  }

  struct FileWell: View {
    let slot: FileSlot
    @Binding var files: [URL]
    var enabled: Bool
    var onChoose: () -> Void
    @State private var dropRejection: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(slot.required ? slot.label : "\(slot.label) (optional)")
          .font(.headline)
        VStack(alignment: .leading, spacing: 10) {
          if files.isEmpty {
            Label(slot.help, systemImage: "arrow.down.doc")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
              HStack {
                Image(systemName: "doc")
                  .foregroundStyle(.secondary)
                Text(file.lastPathComponent)
                  .lineLimit(1)
                Spacer()
                Button {
                  files.remove(at: index)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
              }
            }
          }
          if let message = files.isEmpty ? dropRejection : slot.rejection(for: files) {
            Text(message)
              .font(.callout)
              .foregroundStyle(.red)
          }
          Button(files.isEmpty ? "Choose…" : (slot.allowsMultiple ? "Add…" : "Replace…")) {
            onChoose()
          }
          .disabled(!enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
              .separator.opacity(0.6),
              style: StrokeStyle(lineWidth: 1, dash: files.isEmpty ? [5] : []))
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
          guard enabled else { return false }
          loadDroppedFiles(providers)
          return true
        }
        .onChange(of: files) {
          if slot.rejection(for: files) == nil {
            dropRejection = nil
          }
        }
      }
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) {
      for provider in providers {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url else { return }
          Task { @MainActor in
            guard slot.accepts(url) else {
              dropRejection = slot.rejection(for: [url])
              return
            }
            dropRejection = nil
            if slot.allowsMultiple {
              if !files.contains(url) {
                files.append(url)
              }
            } else {
              files = [url]
            }
          }
        }
      }
    }
  }

  private enum FormItem: Identifiable {
    case field(FormField)
    case presets(label: String, fields: [FormField], group: PresetGroup)

    var id: String {
      switch self {
      case .field(let field):
        field.key
      case .presets(_, _, let group):
        group.id
      }
    }
  }

#endif
