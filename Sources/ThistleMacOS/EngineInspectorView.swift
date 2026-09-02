#if os(macOS) && arch(arm64)

  import AppKit
  import SwiftUI

  import ThistleSupport

  struct EngineInspectorView: View {
    @Environment(EngineController.self) private var controller
    @State private var snapshot: EngineSnapshot

    init() {
      _snapshot = State(initialValue: EngineSnapshot.placeholder(guestURL: nil))
    }

    var body: some View {
      @Bindable var controller = controller
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 16) {
            header
            toggle
            Spacer(minLength: 8)
            actions
          }
          if controller.usesRemote {
            remoteURLField(text: $controller.remoteURLText)
          }
          Text(
            controller.usesRemote
              ? "Uses your Gotenberg API. The local VM is stopped."
              : "Start Engine boots a local guest. Turn Built-in VM off to use a custom URL instead."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if controller.usesRemote {
          remoteFacts
        } else {
          facts
        }

        logSection
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
      .overlay(alignment: .bottom) {
        Divider()
      }
      .task(id: snapshotTaskID) {
        let url = controller.baseURL?.absoluteString
        if controller.isStarting {
          snapshot = EngineSnapshot.placeholder(
            guestURL: url, imageDigest: controller.imageDigest)
          return
        }
        snapshot = await EngineSnapshot.load(
          guestURL: url, imageDigest: controller.imageDigest)
      }
    }

    private var header: some View {
      let chrome = EngineStatusChrome(controller: controller, compact: true)
      return HStack(spacing: 8) {
        Circle()
          .fill(chrome.color)
          .frame(width: 8, height: 8)
        Text("Engine")
          .font(.headline)
        Text(chrome.label)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }

    private var toggle: some View {
      HStack(spacing: 8) {
        Text("Built-in VM")
          .font(.callout)
          .foregroundStyle(.secondary)
        Toggle(
          "Built-in VM",
          isOn: Binding(
            get: { !controller.usesRemote },
            set: { on in
              Task { await controller.setMode(on ? .builtIn : .remote) }
            }
          )
        )
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
        .disabled(controller.isStarting || controller.isWorking)
      }
    }

    private func remoteURLField(text: Binding<String>) -> some View {
      HStack(spacing: 8) {
        TextField("http://127.0.0.1:3000", text: text)
          .textFieldStyle(.roundedBorder)
          .font(.system(.callout, design: .monospaced))
          .frame(maxWidth: .infinity)
          .onSubmit {
            Task { await controller.applyRemoteURL() }
          }
        Button("Connect") {
          Task { await controller.applyRemoteURL() }
        }
        .buttonStyle(.borderless)
        .disabled(controller.isStarting || controller.isWorking)
      }
    }

    private var remoteFacts: some View {
      VStack(alignment: .leading, spacing: 6) {
        fact("Source", "Custom URL")
        fact("API", remoteAPIValue)
        fact("Log", "This app session")
      }
      .textSelection(.enabled)
    }

    private var remoteAPIValue: String {
      if let url = controller.settings.apiURL {
        return url.absoluteString
      }
      let draft = controller.remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines)
      return draft.isEmpty ? "—" : draft
    }

    private var facts: some View {
      VStack(alignment: .leading, spacing: 6) {
        fact("Image", snapshot.image)
        fact("Digest", snapshot.imageDigest ?? "—")
        fact("Init", snapshot.initfs)
        fact("Kernel", kernelValue)
        fact("Rootfs", rootfsValue)
        fact(
          "Store",
          "\(ByteFormat.path(snapshot.storePath))  \(ByteFormat.string(snapshot.storeSize))")
        fact("Log file", logFileValue)
        fact("VM", "\(snapshot.cpus) CPU · \(snapshot.memoryMiB) MiB")
        fact("Guest", snapshot.guestURL ?? "—")
        fact("Container", snapshot.containerID)
      }
      .textSelection(.enabled)
    }

    private var kernelValue: String {
      if snapshot.kernelPresent {
        "\(ByteFormat.path(snapshot.kernelPath))  \(ByteFormat.string(snapshot.kernelSize))"
      } else {
        "Not downloaded"
      }
    }

    private var logFileValue: String {
      ByteFormat.shellPath(Paths.engineLog)
    }

    private var rootfsValue: String {
      if snapshot.rootfsPresent {
        "\(ByteFormat.string(snapshot.rootfsSize))"
      } else {
        "Not unpacked"
      }
    }

    private func fact(_ label: String, _ value: String) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(label)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(width: 72, alignment: .leading)
        Text(value)
          .font(.system(.callout, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .help(value)
      }
    }

    private var actions: some View {
      HStack(spacing: 12) {
        Button("Reveal in Finder") {
          try? FileManager.default.createDirectory(
            at: Paths.appRoot, withIntermediateDirectories: true)
          NSWorkspace.shared.open(Paths.appRoot)
        }
        .buttonStyle(.borderless)
        if let url = controller.baseURL?.absoluteString {
          Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
          }
          .buttonStyle(.borderless)
        }
      }
    }

    private var logSection: some View {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text("Log")
            .font(.callout)
            .foregroundStyle(.secondary)
          Text("Last \(EngineLogEntry.retainedCount) events")
            .font(.caption)
            .foregroundStyle(.tertiary)
          Spacer(minLength: 8)
          if !controller.logs.isEmpty {
            Button("Copy") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(logText, forType: .string)
            }
            .buttonStyle(.borderless)
            Button("Clear") {
              Task { await controller.clearLogs() }
            }
            .buttonStyle(.borderless)
          }
        }
        LogTextView(text: logText, isEmpty: controller.logs.isEmpty)
          .frame(minHeight: 64, maxHeight: 88)
          .padding(8)
          .background(
            .quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
      }
    }

    private var logText: String {
      controller.logs.map { entry in
        "\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.message)"
      }.joined(separator: "\n")
    }

    private var snapshotTaskID: String {
      let digest = controller.imageDigest ?? ""
      return switch controller.status {
      case .starting:
        "starting"
      case .idle:
        "idle:\(digest)"
      case .running(let url):
        "running:\(url):\(digest)"
      case .failed(let message):
        "failed:\(message):\(digest)"
      }
    }
  }

  private struct LogTextView: NSViewRepresentable {
    var text: String
    var isEmpty: Bool

    func makeNSView(context: Context) -> NSScrollView {
      let scrollView = NSTextView.scrollableTextView()
      scrollView.drawsBackground = false
      scrollView.borderType = .noBorder
      scrollView.hasHorizontalScroller = false
      scrollView.autohidesScrollers = true

      let textView = scrollView.documentView as! NSTextView
      textView.drawsBackground = false
      textView.isEditable = false
      textView.isRichText = false
      textView.isHorizontallyResizable = false
      textView.textContainerInset = .zero
      textView.textContainer?.lineFragmentPadding = 0
      textView.font = NSFont.monospacedSystemFont(
        ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
        weight: .regular
      )
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let textView = scrollView.documentView as? NSTextView else { return }
      let display = isEmpty ? "No events yet." : text
      let changed = textView.string != display
      if changed {
        textView.string = display
      }
      textView.isSelectable = !isEmpty
      textView.textColor = isEmpty ? .tertiaryLabelColor : .labelColor
      if changed && !isEmpty {
        DispatchQueue.main.async {
          textView.scrollToEndOfDocument(nil)
        }
      }
    }
  }

#endif
