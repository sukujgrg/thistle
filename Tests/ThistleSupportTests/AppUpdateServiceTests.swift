import Foundation
import Testing

@testable import ThistleSupport

struct AppUpdateServiceTests {
  @Test func checkForUpdateReturnsLatestReleaseWhenSeveralVersionsBehind() async throws {
    let service = makeService(
      currentVersion: "1.0.0",
      responseJSON: """
        {
          "tag_name": "v1.3.0",
          "html_url": "https://example.com/releases/v1.3.0",
          "assets": [
            {
              "name": "Thistle-1.3.0-notarized.zip",
              "browser_download_url": "https://example.com/thistle.zip"
            },
            {
              "name": "Thistle-1.3.0-notarized.zip.sha256",
              "browser_download_url": "https://example.com/thistle.zip.sha256"
            }
          ]
        }
        """
    )

    let release = try await service.checkForUpdate()
    #expect(release?.version == "1.3.0")
    #expect(release?.asset?.name == "Thistle-1.3.0-notarized.zip")
    #expect(release?.checksumAsset?.name == "Thistle-1.3.0-notarized.zip.sha256")
  }

  @Test func checkForUpdateReturnsNilWhenAlreadyOnLatestRelease() async throws {
    let service = makeService(
      currentVersion: "1.3.0",
      responseJSON: """
        {
          "tag_name": "v1.3.0",
          "html_url": "https://example.com/releases/v1.3.0",
          "assets": []
        }
        """
    )

    let release = try await service.checkForUpdate()
    #expect(release == nil)
  }

  @Test func checkForUpdateReturnsNilWhenInstalledVersionIsNewerThanLatestRelease() async throws {
    let service = makeService(
      currentVersion: "1.4.0",
      responseJSON: """
        {
          "tag_name": "v1.3.0",
          "html_url": "https://example.com/releases/v1.3.0",
          "assets": []
        }
        """
    )

    let release = try await service.checkForUpdate()
    #expect(release == nil)
  }

  @Test func checkForUpdateThrowsWhenLatestReleaseRequestFails() async {
    let service = makeService(
      currentVersion: "1.0.0",
      responseJSON: "{}",
      statusCode: 500
    )

    await #expect(throws: AppUpdateError.updateCheckFailed) {
      _ = try await service.checkForUpdate()
    }
  }
}

private func makeService(
  currentVersion: String,
  responseJSON: String,
  statusCode: Int = 200
) -> GitHubReleaseUpdateService {
  let latestReleaseURL = URL(string: "https://example.com/releases/latest")!
  return GitHubReleaseUpdateService(
    latestReleaseURL: latestReleaseURL,
    currentVersionProvider: { currentVersion },
    dataLoader: { request in
      let response = HTTPURLResponse(
        url: request.url ?? latestReleaseURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      )!
      return (Data(responseJSON.utf8), response)
    }
  )
}
