import Foundation
import Observation
import os

@MainActor
@Observable
public final class AppUpdateViewModel {
  public private(set) var availableRelease: AppUpdateRelease?
  public var checkAlert: AppUpdateCheckAlert?
  public private(set) var isDownloading = false
  public private(set) var isInstalling = false

  @ObservationIgnored private let service: any AppUpdateServicing
  @ObservationIgnored private let runUpdaterAction: (URL) async throws -> Void
  @ObservationIgnored private let terminateAction: @MainActor () -> Void
  @ObservationIgnored private let logger = Logger(subsystem: "dev.thistle", category: "AppUpdate")
  @ObservationIgnored private var hasChecked = false
  @ObservationIgnored private var checkTask: Task<Void, Never>?
  @ObservationIgnored private var downloadTask: Task<Void, Never>?

  public init(
    service: any AppUpdateServicing = GitHubReleaseUpdateService(),
    installUpdateAction: ((URL) async throws -> Void)? = nil,
    terminateAction: @escaping @MainActor () -> Void = {}
  ) {
    self.service = service
    self.runUpdaterAction =
      installUpdateAction ?? { _ in
        throw AppUpdateInstallError.missingUpdater
      }
    self.terminateAction = terminateAction
  }

  public func checkForUpdatesIfNeeded() {
    guard !hasChecked else {
      return
    }

    checkForUpdates(reportsResult: false)
  }

  public func checkForUpdates(reportsResult: Bool = true) {
    hasChecked = true
    checkTask?.cancel()
    checkTask = Task {
      do {
        let release = try await service.checkForUpdate()
        availableRelease = release
        if reportsResult, release == nil {
          checkAlert = AppUpdateCheckAlert(
            title: "Thistle is up to date",
            message: "You are running the latest available version."
          )
        }
      } catch {
        logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        availableRelease = nil
        if reportsResult {
          checkAlert = AppUpdateCheckAlert(
            title: "Unable to check for updates",
            message: "Try again later, or check the GitHub releases page manually.",
            releaseURL: AppUpdateRelease.releasesPageURL
          )
        }
      }
    }
  }

  public func downloadAndInstallUpdate() {
    guard let release = availableRelease,
      !isDownloading,
      !isInstalling
    else {
      return
    }

    isDownloading = true
    downloadTask?.cancel()
    downloadTask = Task {
      defer {
        isDownloading = false
      }

      do {
        let download = try await service.downloadUpdate(release)
        try await installUpdate(from: download.archiveURL)
      } catch {
        logger.error(
          "Update install preparation failed: \(error.localizedDescription, privacy: .public)")
        checkAlert = AppUpdateCheckAlert(
          title: "Unable to install update",
          message: """
            \(error.localizedDescription)

            You can download Thistle \(release.version) from the release page.
            """,
          releaseURL: release.releaseURL
        )
      }
    }
  }

  private func installUpdate(from archiveURL: URL) async throws {
    try await runUpdaterAction(archiveURL)
    isInstalling = true
    terminateAction()
  }
}

public enum AppUpdateInstallError: Error, LocalizedError, Sendable {
  case missingUpdater

  public var errorDescription: String? {
    switch self {
    case .missingUpdater:
      "This installed copy of Thistle does not include the updater helper."
    }
  }
}

public struct AppUpdateCheckAlert: Identifiable, Equatable, Sendable {
  public let id = UUID()
  public let title: String
  public let message: String
  public let releaseURL: URL?

  public init(title: String, message: String, releaseURL: URL? = nil) {
    self.title = title
    self.message = message
    self.releaseURL = releaseURL
  }
}
