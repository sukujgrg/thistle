import Foundation
import Testing

@testable import ThistleSupport

@MainActor
struct AppUpdateViewModelTests {
  @Test func installFailureShowsAlertWithReleaseURL() async throws {
    let releaseURL = try #require(URL(string: "https://example.com/releases/v1.1.0"))
    let release = AppUpdateRelease(
      version: "1.1.0",
      releaseURL: releaseURL,
      asset: GitHubReleaseAssetModel(
        name: "Thistle-1.1.0-notarized.zip",
        downloadURL: try #require(URL(string: "https://example.com/thistle.zip"))
      ),
      checksumAsset: GitHubReleaseAssetModel(
        name: "Thistle-1.1.0-notarized.zip.sha256",
        downloadURL: try #require(URL(string: "https://example.com/thistle.zip.sha256"))
      )
    )
    let viewModel = AppUpdateViewModel(
      service: FakeAppUpdateService(
        release: release,
        downloadedUpdate: AppDownloadedUpdate(
          archiveURL: URL(fileURLWithPath: "/tmp/thistle-test-update.zip")
        )
      ),
      installUpdateAction: { _ in
        throw AppUpdateViewModelTestError.installFailed
      }
    )

    viewModel.checkForUpdates()
    try await waitUntil { viewModel.availableRelease != nil }
    viewModel.downloadAndInstallUpdate()
    try await waitUntil { viewModel.checkAlert != nil }

    let alert = try #require(viewModel.checkAlert)
    #expect(alert.title == "Unable to install update")
    #expect(alert.releaseURL == releaseURL)
    #expect(alert.message.contains("Install failed"))
  }

  @Test func installRunsToCompletionBeforeTerminate() async throws {
    let releaseURL = try #require(URL(string: "https://example.com/releases/v1.1.0"))
    let release = AppUpdateRelease(
      version: "1.1.0",
      releaseURL: releaseURL,
      asset: GitHubReleaseAssetModel(
        name: "Thistle-1.1.0-notarized.zip",
        downloadURL: try #require(URL(string: "https://example.com/thistle.zip"))
      ),
      checksumAsset: GitHubReleaseAssetModel(
        name: "Thistle-1.1.0-notarized.zip.sha256",
        downloadURL: try #require(URL(string: "https://example.com/thistle.zip.sha256"))
      )
    )
    var events: [String] = []
    let viewModel = AppUpdateViewModel(
      service: FakeAppUpdateService(
        release: release,
        downloadedUpdate: AppDownloadedUpdate(
          archiveURL: URL(fileURLWithPath: "/tmp/thistle-test-update.zip")
        )
      ),
      installUpdateAction: { _ in
        events.append("install")
      },
      terminateAction: {
        events.append("terminate")
      }
    )

    viewModel.checkForUpdates()
    try await waitUntil { viewModel.availableRelease != nil }
    viewModel.downloadAndInstallUpdate()
    try await waitUntil { viewModel.isInstalling }
    #expect(events == ["install", "terminate"])
  }

  @Test func checkFailureAlertIncludesReleasesPageURL() async throws {
    let viewModel = AppUpdateViewModel(
      service: FakeAppUpdateService(checkError: AppUpdateError.updateCheckFailed)
    )

    viewModel.checkForUpdates()
    try await waitUntil { viewModel.checkAlert != nil }

    let alert = try #require(viewModel.checkAlert)
    #expect(alert.title == "Unable to check for updates")
    #expect(alert.releaseURL == AppUpdateRelease.releasesPageURL)
  }
}

private enum AppUpdateViewModelTestError: Error, LocalizedError {
  case installFailed

  var errorDescription: String? {
    switch self {
    case .installFailed:
      "Install failed"
    }
  }
}

private actor FakeAppUpdateService: AppUpdateServicing {
  let release: AppUpdateRelease?
  let downloadedUpdate: AppDownloadedUpdate
  let checkError: Error?

  init(
    release: AppUpdateRelease? = nil,
    downloadedUpdate: AppDownloadedUpdate = AppDownloadedUpdate(
      archiveURL: URL(fileURLWithPath: "/tmp/thistle-test-update.zip")
    ),
    checkError: Error? = nil
  ) {
    self.release = release
    self.downloadedUpdate = downloadedUpdate
    self.checkError = checkError
  }

  func checkForUpdate() async throws -> AppUpdateRelease? {
    if let checkError {
      throw checkError
    }
    return release
  }

  func downloadUpdate(_ release: AppUpdateRelease) async throws -> AppDownloadedUpdate {
    downloadedUpdate
  }
}

@MainActor
private func waitUntil(
  timeout: Duration = .seconds(2),
  _ predicate: @MainActor () -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if predicate() {
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("timed out waiting for update state")
}
