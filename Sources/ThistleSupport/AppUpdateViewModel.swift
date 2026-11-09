import Foundation
import Observation
import os

public enum AppUpdatePhase: Equatable, Sendable {
  case idle
  case checking
  case available(AppUpdateRelease)
  case upToDate(AppUpdateCheckAlert)
  case downloading(AppUpdateRelease)
  case installing(AppUpdateRelease)
  case failed(AppUpdateCheckAlert)
}

@MainActor
@Observable
public final class AppUpdateViewModel {
  public private(set) var phase: AppUpdatePhase = .idle

  @ObservationIgnored private let service: any AppUpdateServicing
  @ObservationIgnored private let runUpdaterAction: (URL) async throws -> Void
  @ObservationIgnored private let terminateAction: @MainActor () -> Void
  @ObservationIgnored private let logger = Logger(subsystem: "dev.thistle", category: "AppUpdate")
  @ObservationIgnored private var hasChecked = false
  @ObservationIgnored private var checkTask: Task<Void, Never>?
  @ObservationIgnored private var downloadTask: Task<Void, Never>?
  @ObservationIgnored private var retainedRelease: AppUpdateRelease?

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

  public var availableRelease: AppUpdateRelease? {
    switch phase {
    case .available(let release), .downloading(let release), .installing(let release):
      release
    case .failed:
      retainedRelease
    default:
      nil
    }
  }

  public var checkAlert: AppUpdateCheckAlert? {
    get {
      switch phase {
      case .failed(let alert), .upToDate(let alert):
        alert
      default:
        nil
      }
    }
    set {
      guard newValue == nil else { return }
      switch phase {
      case .failed:
        if let retainedRelease {
          phase = .available(retainedRelease)
        } else {
          phase = .idle
        }
      case .upToDate:
        phase = .idle
      default:
        break
      }
    }
  }

  public var isDownloading: Bool {
    if case .downloading = phase { return true }
    return false
  }

  public var isInstalling: Bool {
    if case .installing = phase { return true }
    return false
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
    phase = .checking
    checkTask = Task {
      do {
        let release = try await service.checkForUpdate()
        if let release {
          retainedRelease = release
          phase = .available(release)
        } else if reportsResult {
          retainedRelease = nil
          phase = .upToDate(
            AppUpdateCheckAlert(
              title: "Thistle is up to date",
              message: "You are running the latest available version."
            ))
        } else {
          retainedRelease = nil
          phase = .idle
        }
      } catch {
        logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        retainedRelease = nil
        if reportsResult {
          phase = .failed(
            AppUpdateCheckAlert(
              title: "Unable to check for updates",
              message: "Try again later, or check the GitHub releases page manually.",
              releaseURL: AppUpdateRelease.releasesPageURL
            ))
        } else {
          phase = .idle
        }
      }
    }
  }

  public func downloadAndInstallUpdate() {
    guard case .available(let release) = phase else {
      return
    }

    phase = .downloading(release)
    downloadTask?.cancel()
    downloadTask = Task {
      do {
        let download = try await service.downloadUpdate(release)
        try await installUpdate(from: download.archiveURL, release: release)
      } catch {
        logger.error(
          "Update install preparation failed: \(error.localizedDescription, privacy: .public)")
        retainedRelease = release
        phase = .failed(
          AppUpdateCheckAlert(
            title: "Unable to install update",
            message: """
              \(error.localizedDescription)

              You can download Thistle \(release.version) from the release page.
              """,
            releaseURL: release.releaseURL
          ))
      }
    }
  }

  private func installUpdate(from archiveURL: URL, release: AppUpdateRelease) async throws {
    try await runUpdaterAction(archiveURL)
    phase = .installing(release)
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
