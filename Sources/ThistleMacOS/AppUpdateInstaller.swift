#if os(macOS) && arch(arm64)

  import AppKit
  import Foundation

  import ThistleSupport

  @MainActor
  enum AppUpdateInstaller {
    static func makeViewModel() -> AppUpdateViewModel {
      AppUpdateViewModel(
        installUpdateAction: run,
        terminateAction: {
          AppDelegate.isInstallingUpdate = true
          NSApp.terminate(nil)
        }
      )
    }

    static func run(with archiveURL: URL) async throws {
      await AppDelegate.shared?.controller?.prepareForUpdate()
      try startUpdater(archiveURL: archiveURL)
      AppDelegate.shared?.controller?.prepareForTermination()
    }

    private static func startUpdater(archiveURL: URL) throws {
      guard
        let helperURL = Bundle.main.url(
          forResource: "ThistleUpdater",
          withExtension: nil,
          subdirectory: "MacOS"
        )
          ?? Bundle.main.executableURL?
          .deletingLastPathComponent()
          .appendingPathComponent("ThistleUpdater")
      else {
        throw AppUpdateInstallError.missingUpdater
      }

      let process = Process()
      process.executableURL = helperURL
      process.arguments = [
        "--archive",
        archiveURL.path,
        "--target",
        Bundle.main.bundleURL.path,
        "--bundle-id",
        Bundle.main.bundleIdentifier ?? "dev.thistle",
        "--parent-pid",
        "\(ProcessInfo.processInfo.processIdentifier)",
      ]

      try process.run()
    }
  }

#endif
