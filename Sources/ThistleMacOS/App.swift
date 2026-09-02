import SwiftUI

#if os(macOS) && arch(arm64)

  import AppKit
  import Darwin

  import ThistleSupport

  @main
  struct ThistleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = EngineController()

    var body: some Scene {
      Window("Thistle", id: "main") {
        ContentView()
          .environment(controller)
          .onAppear {
            appDelegate.controller = controller
            controller.connect()
          }
      }
      .defaultSize(width: 1100, height: 720)
      .windowToolbarStyle(.unified)
      .defaultLaunchBehavior(.presented)
      .commands {
        CommandGroup(after: .appInfo) {
          Button("Check for Updates...") {
            NotificationCenter.default.post(name: .checkForUpdates, object: nil)
          }
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {
          Button("Save As…") {
            Task { await controller.saveCurrentResult(defaultJSONName: "") }
          }
          .keyboardShortcut("s")
          .disabled(!controller.canSaveResult || controller.isWorking)
        }
        CommandMenu("Engine") {
          if controller.usesRemote {
            Button("Connect") {
              Task { await controller.start() }
            }
            .disabled(controller.isStarting || controller.isWorking)
          } else {
            Button("Start Engine") {
              Task { await controller.start() }
            }
            .disabled(controller.isRunning || controller.isStarting || controller.isWorking)
            Button("Stop Engine") {
              Task { await controller.stop() }
            }
            .disabled(!controller.isRunning || controller.isStarting || controller.isWorking)
            Button("Restart Engine") {
              Task { await controller.restart() }
            }
            .disabled(!controller.isRunning || controller.isStarting || controller.isWorking)
            Divider()
            Button("Refresh Image") {
              Task { await controller.refreshImage() }
            }
            .disabled(controller.isStarting || controller.isWorking)
            Button("Reset Engine…") {
              controller.confirmReset = true
            }
            .disabled(controller.isStarting || controller.isWorking)
          }
        }
      }
    }
  }

  @MainActor
  final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    static var isInstallingUpdate = false

    var controller: EngineController?
    private var instanceLock: FileHandle?

    func applicationWillFinishLaunching(_ notification: Notification) {
      Self.shared = self
      if let lock = InstanceLock.acquire() {
        instanceLock = lock
        try? Paths.ensureDirectories()
        Paths.clearJobs()
        return
      }
      InstanceLock.activateExisting()
      NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
      controller?.connect()
    }

    func applicationWillTerminate(_ notification: Notification) {
      guard instanceLock != nil else { return }
      controller?.prepareForTermination()
    }

    func applicationShouldHandleReopen(
      _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
      if !flag {
        sender.windows.first?.makeKeyAndOrderFront(nil)
      }
      return true
    }
  }

  /// One GUI process. The VM lives in the LaunchAgent.
  private enum InstanceLock {
    static func acquire() -> FileHandle? {
      try? Paths.ensureDirectories()
      let path = Paths.instanceLock.path(percentEncoded: false)
      let fd = open(path, O_CREAT | O_RDWR, 0o644)
      guard fd >= 0 else { return nil }
      if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return nil
      }
      return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    static func activateExisting() {
      guard let bundleID = Bundle.main.bundleIdentifier else { return }
      let selfPID = ProcessInfo.processInfo.processIdentifier
      let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first { $0.processIdentifier != selfPID && !$0.isTerminated }
      other?.activate()
    }
  }

  extension Notification.Name {
    static let checkForUpdates = Notification.Name("checkForUpdates")
  }

#else

  @main
  struct ThistleApp: App {
    var body: some Scene {
      Window("Thistle", id: "main") {
        Text("Thistle requires macOS 26 on Apple silicon.")
          .padding(24)
          .frame(minWidth: 360, minHeight: 120)
      }
      .windowResizability(.contentSize)
    }
  }

#endif
