import Foundation
import Testing

@testable import ThistleSupport

struct AppUpdateReleaseModelTests {
  @Test func primaryDownloadAssetSelectsAppZip() throws {
    let release = GitHubReleaseResponseModel(
      tagName: "v1.21",
      htmlURL: try #require(URL(string: "https://example.com/releases/v1.21")),
      assets: [
        GitHubReleaseAssetModel(
          name: "Thistle-1.21-notarized.zip.sha256",
          downloadURL: try #require(URL(string: "https://example.com/thistle.zip.sha256"))
        ),
        GitHubReleaseAssetModel(
          name: "Thistle-1.21-notarized.zip",
          downloadURL: try #require(URL(string: "https://example.com/thistle.zip"))
        ),
      ]
    )

    #expect(release.primaryDownloadAsset?.name == "Thistle-1.21-notarized.zip")
  }

  @Test func primaryDownloadAssetIgnoresDmgBecauseUpdaterRequiresZip() throws {
    let release = GitHubReleaseResponseModel(
      tagName: "v1.21",
      htmlURL: try #require(URL(string: "https://example.com/releases/v1.21")),
      assets: [
        GitHubReleaseAssetModel(
          name: "Thistle-1.21-notarized.dmg",
          downloadURL: try #require(URL(string: "https://example.com/thistle.dmg"))
        ),
        GitHubReleaseAssetModel(
          name: "Thistle-1.21-notarized.zip",
          downloadURL: try #require(URL(string: "https://example.com/thistle.zip"))
        ),
      ]
    )

    #expect(release.primaryDownloadAsset?.name == "Thistle-1.21-notarized.zip")
  }

  @Test func primaryChecksumAssetSelectsMatchingChecksum() throws {
    let release = GitHubReleaseResponseModel(
      tagName: "v1.21",
      htmlURL: try #require(URL(string: "https://example.com/releases/v1.21")),
      assets: [
        GitHubReleaseAssetModel(
          name: "unrelated.zip.sha256",
          downloadURL: try #require(URL(string: "https://example.com/unrelated.zip.sha256"))
        ),
        GitHubReleaseAssetModel(
          name: "Thistle-1.21-notarized.zip",
          downloadURL: try #require(URL(string: "https://example.com/thistle.zip"))
        ),
        GitHubReleaseAssetModel(
          name: "Thistle-1.21-notarized.zip.sha256",
          downloadURL: try #require(URL(string: "https://example.com/thistle.zip.sha256"))
        ),
      ]
    )

    #expect(release.primaryChecksumAsset?.name == "Thistle-1.21-notarized.zip.sha256")
  }

  @Test func checksumParserReadsShasumFormat() {
    let checksum = AppUpdateChecksumParser.expectedChecksum(
      from: "ABCDEF123456  Thistle-1.21-notarized.zip\n"
    )
    #expect(checksum == "abcdef123456")
  }

  @Test func checksumParserReadsTabSeparatedFormat() {
    let checksum = AppUpdateChecksumParser.expectedChecksum(
      from: "abcdef123456\tThistle-1.21-notarized.zip\n"
    )
    #expect(checksum == "abcdef123456")
  }

  @Test func checksumParserRejectsBlankText() {
    #expect(AppUpdateChecksumParser.expectedChecksum(from: " \n\t") == nil)
  }
}
