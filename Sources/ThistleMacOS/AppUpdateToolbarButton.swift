#if os(macOS) && arch(arm64)

  import AppKit
  import SwiftUI

  import ThistleSupport

  struct AppUpdateToolbarButton: View {
    var viewModel: AppUpdateViewModel

    var body: some View {
      if let release = viewModel.availableRelease {
        if release.isInstallable {
          Button {
            viewModel.downloadAndInstallUpdate()
          } label: {
            Label(
              buttonTitle,
              systemImage: viewModel.isDownloading
                ? "arrow.down.circle.dotted" : "arrow.down.circle"
            )
          }
          .labelStyle(.titleAndIcon)
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.isDownloading || viewModel.isInstalling)
          .help("Install Thistle \(release.version)")
        } else {
          Button {
            NSWorkspace.shared.open(release.releaseURL)
          } label: {
            Label("Release", systemImage: "safari")
          }
          .labelStyle(.titleAndIcon)
          .buttonStyle(.bordered)
          .help("Open Thistle \(release.version) release")
        }
      }
    }

    private var buttonTitle: String {
      if viewModel.isInstalling {
        return "Installing"
      }
      if viewModel.isDownloading {
        return "Downloading"
      }
      return "Update"
    }
  }

#endif
