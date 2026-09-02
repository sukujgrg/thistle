#if os(macOS) && arch(arm64)

  import AppKit
  import SwiftUI

  import ThistleSupport

  struct ContentView: View {
    @Environment(EngineController.self) private var controller
    @State private var selectedID: String? = ConvertAction.all.first?.id
    @State private var search = ""
    @State private var copied = false
    @State private var hoveredID: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var appUpdateViewModel = AppUpdateInstaller.makeViewModel()

    private var selectedAction: ConvertAction? {
      ConvertAction.all.first { $0.id == selectedID }
    }

    var body: some View {
      @Bindable var controller = controller
      VStack(spacing: 0) {
        if controller.inspectorPresented {
          EngineInspectorView()
            .environment(controller)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        NavigationSplitView(columnVisibility: $columnVisibility) {
          sidebar
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
          if let action = selectedAction {
            ActionDetailView(action: action)
              .id(action.id)
          } else {
            ContentUnavailableView(
              "Select an action",
              systemImage: "doc.richtext",
              description: Text("Chromium, LibreOffice, and PDF engines are on the left.")
            )
          }
        }
        .navigationTitle("Thistle")
      }
      .animation(.snappy(duration: 0.22), value: controller.inspectorPresented)
      .confirmationDialog(
        "Reset Engine stops the VM and deletes downloaded engine data, temporary jobs, and logs. Settings are kept. The next start downloads everything again.",
        isPresented: $controller.confirmReset, titleVisibility: .visible
      ) {
        Button("Reset Engine", role: .destructive) {
          Task { await controller.resetEngine() }
        }
        Button("Cancel", role: .cancel) {}
      }
      .alert(
        appUpdateViewModel.checkAlert?.title ?? "Update",
        isPresented: Binding(
          get: { appUpdateViewModel.checkAlert != nil },
          set: { if !$0 { appUpdateViewModel.checkAlert = nil } }
        ),
        presenting: appUpdateViewModel.checkAlert
      ) { alert in
        if let releaseURL = alert.releaseURL {
          Button("Open Release") {
            NSWorkspace.shared.open(releaseURL)
          }
        }
        Button("OK", role: .cancel) {}
      } message: { alert in
        Text(alert.message)
      }
      .onAppear {
        appUpdateViewModel.checkForUpdatesIfNeeded()
      }
      .onReceive(NotificationCenter.default.publisher(for: .checkForUpdates)) { _ in
        appUpdateViewModel.checkForUpdates()
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: 8) {
            AppUpdateToolbarButton(viewModel: appUpdateViewModel)
            engineStatus
            engineButton
            if !controller.hasUnappliedRemoteURL,
              case .running(let url) = controller.status
            {
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                copied = true
              } label: {
                Text(copied ? "Copied" : "Copy URL")
              }
              .buttonStyle(ToolbarPillButtonStyle())
              .onChange(of: url) { _, _ in
                copied = false
              }
            }
          }
        }
        .sharedBackgroundVisibility(.hidden)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if case .failed(let message) = controller.status {
          Text(message)
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.08))
        }
      }
    }

    private var sidebar: some View {
      VStack(spacing: 0) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search actions", text: $search)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          .quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)

        List(selection: $selectedID) {
          ForEach(filteredGroups, id: \.0.id) { group, actions in
            Section(group.rawValue) {
              ForEach(actions) { action in
                SidebarActionRow(action: action, isSelected: selectedID == action.id)
                  .tag(action.id)
                  .listRowSeparator(.hidden)
                  .listRowBackground(sidebarRowBackground(for: action.id))
                  .onHover { hovering in
                    hoveredID = hovering ? action.id : (hoveredID == action.id ? nil : hoveredID)
                  }
              }
            }
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
      }
    }

    @ViewBuilder
    private func sidebarRowBackground(for id: String) -> some View {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(rowFill(for: id))
        .padding(.horizontal, 4)
    }

    private func rowFill(for id: String) -> Color {
      if selectedID == id {
        Color.accentColor.opacity(0.18)
      } else if hoveredID == id {
        Color.primary.opacity(0.07)
      } else {
        .clear
      }
    }

    private var filteredGroups: [(ActionGroup, [ConvertAction])] {
      ConvertAction.grouped().compactMap { group, actions in
        let filtered = actions.filter { action in
          search.isEmpty
            || action.title.localizedCaseInsensitiveContains(search)
            || action.subtitle.localizedCaseInsensitiveContains(search)
            || action.path.localizedCaseInsensitiveContains(search)
        }
        guard !filtered.isEmpty else { return nil }
        return (group, filtered)
      }
    }

    private var engineStatus: some View {
      let chrome = EngineStatusChrome(controller: controller, compact: false)
      return Button {
        controller.inspectorPresented.toggle()
      } label: {
        HStack(spacing: 6) {
          Circle()
            .fill(chrome.color)
            .frame(width: 8, height: 8)
          Text(chrome.label)
            .foregroundStyle(.secondary)
          if controller.isStarting {
            ProgressView()
              .controlSize(.small)
          }
          Image(systemName: controller.inspectorPresented ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.primary.opacity(controller.inspectorPresented ? 0.14 : 0.08), in: Capsule())
      }
      .buttonStyle(.plain)
      .help("Engine inspector")
    }

    @ViewBuilder
    private var engineButton: some View {
      if controller.usesRemote {
        if controller.remoteNeedsConnection {
          Button("Connect") {
            Task { await controller.start() }
          }
          .buttonStyle(ToolbarPillButtonStyle())
          .disabled(controller.isStarting)
        }
      } else {
        Menu {
          if controller.isRunning {
            Button("Restart") {
              Task { await controller.restart() }
            }
          }
          Button("Refresh Image") {
            Task { await controller.refreshImage() }
          }
          Divider()
          Button("Reset…", role: .destructive) {
            controller.confirmReset = true
          }
        } label: {
          Text(controller.isRunning ? "Stop Engine" : "Start Engine")
        } primaryAction: {
          Task {
            if controller.isRunning {
              await controller.stop()
            } else {
              await controller.start()
            }
          }
        }
        .menuIndicator(.visible)
        .buttonStyle(ToolbarPillButtonStyle())
        .disabled(controller.isStarting || controller.isWorking)
      }
    }

  }

  private struct ToolbarPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
          .primary.opacity(configuration.isPressed ? 0.16 : 0.10),
          in: Capsule()
        )
        .opacity(isEnabled ? 1 : 0.45)
    }
  }

  private struct SidebarActionRow: View {
    let action: ConvertAction
    let isSelected: Bool

    var body: some View {
      HStack(alignment: .center, spacing: 8) {
        Image(systemName: action.icon)
          .frame(width: 18)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        VStack(alignment: .leading, spacing: 1) {
          Text(action.title)
          Text(action.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .help(action.subtitle)
    }
  }

  #Preview {
    ContentView()
      .environment(EngineController())
  }

#endif
