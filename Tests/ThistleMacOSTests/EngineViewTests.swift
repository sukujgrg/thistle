#if os(macOS) && arch(arm64)
  import AppKit
  import Foundation
  import SwiftUI
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  @MainActor
  struct EngineViewTests {
    @Test func authenticationEditsRequireReconnection() {
      let controller = EngineController(settings: EngineSettings(mode: .remote))
      controller.status = .running("https://engine.example")
      #expect(!controller.hasUnappliedRemoteURL)
      controller.remoteCredentials = RemoteCredentials(
        authentication: .bearer, secret: "test-token")
      #expect(controller.hasUnappliedRemoteURL)
      #expect(!controller.canSubmitJobs)
      #expect(
        EngineStatusChrome(controller: controller, compact: true).label == "Connection changed")
    }

    @Test func renderControlsForVisualInspection() throws {
      guard let directory = ProcessInfo.processInfo.environment["THISTLE_UI_QA"] else { return }
      let output = URL(fileURLWithPath: directory)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      let controller = EngineController(settings: EngineSettings(mode: .remote))
      controller.remoteURLText = "https://engine.example/api"
      controller.remoteCredentials = RemoteCredentials(
        authentication: .basic, username: "example", secret: "test-password")
      controller.gotenbergVersion = "8.37.0"
      try render(
        EngineInspectorView().environment(controller).frame(width: 850),
        to: output.appendingPathComponent("remote-auth.png"))
      var image = PDFMark()
      image.source = .image
      image.files = [URL(fileURLWithPath: "/tmp/logo.png")]
      let first = PDFMark(text: "CONFIDENTIAL")
      var last = PDFMark(text: "DRAFT")
      last.pages = "2-3"
      last.options = #"{"op":"0.35","rot":"45"}"#
      try render(
        PDFMarkEditor(prefix: "stamp", marks: .constant([first, image, last]), enabled: true)
          .padding(24).frame(width: 750), to: output.appendingPathComponent("multiple-stamps.png"))
    }

    private func render(_ content: some View, to path: URL) throws {
      // ImageRenderer cannot draw AppKit text fields, buttons, or text editors.
      // Cache an actual hosting view attached to an off-screen native window.
      _ = NSApplication.shared
      let host = NSHostingView(
        rootView: content.environment(\.colorScheme, .light)
          .foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor)))
      let size = host.fittingSize
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: .aqua)
      window.contentView = host
      window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
      window.orderFront(nil)
      defer { window.close() }
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: path)
    }
  }
#endif
