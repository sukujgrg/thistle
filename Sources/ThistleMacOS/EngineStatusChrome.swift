#if os(macOS) && arch(arm64)

  import SwiftUI

  @MainActor
  struct EngineStatusChrome {
    let color: Color
    let label: String

    init(controller: EngineController, compact: Bool) {
      if controller.highlightsUnappliedRemoteURL {
        color = .orange
        label = "URL changed"
        return
      }
      color =
        switch controller.status {
        case .idle: .secondary
        case .starting: .orange
        case .running: .green
        case .failed: .red
        }
      label =
        switch controller.status {
        case .idle:
          controller.usesRemote ? "Custom URL" : (compact ? "Stopped" : "Engine stopped")
        case .starting(let phase):
          phase
        case .running:
          controller.usesRemote ? "Connected" : (compact ? "Running" : "Engine running")
        case .failed:
          compact ? "Failed" : (controller.usesRemote ? "Unreachable" : "Engine failed")
        }
    }
  }

#endif
