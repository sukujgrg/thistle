import CryptoKit
import Foundation

public protocol AppUpdateServicing: Sendable {
  func checkForUpdate() async throws -> AppUpdateRelease?
  func downloadUpdate(_ release: AppUpdateRelease) async throws -> AppDownloadedUpdate
}

public actor GitHubReleaseUpdateService: AppUpdateServicing {
  public static let latestReleaseURL = URL(
    string: "https://api.github.com/repos/sukujgrg/thistle/releases/latest")!

  private let latestReleaseURL: URL
  private let currentVersionProvider: @Sendable () -> String
  private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  private let downloadLoader: @Sendable (URL) async throws -> (URL, URLResponse)

  public init(
    session: URLSession = .shared,
    latestReleaseURL: URL = GitHubReleaseUpdateService.latestReleaseURL,
    currentVersionProvider: @escaping @Sendable () -> String = {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
  ) {
    self.init(
      latestReleaseURL: latestReleaseURL,
      currentVersionProvider: currentVersionProvider,
      dataLoader: { request in
        try await session.data(for: request)
      },
      downloadLoader: { url in
        try await session.download(from: url)
      }
    )
  }

  init(
    latestReleaseURL: URL,
    currentVersionProvider: @escaping @Sendable () -> String,
    dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
    downloadLoader: @escaping @Sendable (URL) async throws -> (URL, URLResponse) = { _ in
      throw AppUpdateError.downloadFailed
    }
  ) {
    self.latestReleaseURL = latestReleaseURL
    self.currentVersionProvider = currentVersionProvider
    self.dataLoader = dataLoader
    self.downloadLoader = downloadLoader
  }

  public func checkForUpdate() async throws -> AppUpdateRelease? {
    var request = URLRequest(url: latestReleaseURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("thistle", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await dataLoader(request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw AppUpdateError.updateCheckFailed
    }

    let release = try JSONDecoder().decode(GitHubReleaseResponseModel.self, from: data)
    guard
      let latestVersion = AppVersionModel(release.tagName),
      let currentVersion = AppVersionModel(currentVersionProvider()),
      latestVersion > currentVersion
    else {
      return nil
    }

    return AppUpdateRelease(
      version: latestVersion.displayValue,
      releaseURL: release.htmlURL,
      asset: release.primaryDownloadAsset,
      checksumAsset: release.primaryChecksumAsset
    )
  }

  public func downloadUpdate(_ release: AppUpdateRelease) async throws -> AppDownloadedUpdate {
    guard let asset = release.asset else {
      throw AppUpdateError.missingReleaseAsset
    }

    let (temporaryURL, response) = try await downloadLoader(asset.downloadURL)
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw AppUpdateError.downloadFailed
    }

    let destinationDirectory = try updatesDirectory()
    let destinationURL = destinationDirectory.appendingPathComponent(asset.name)
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

    guard let checksumAsset = release.checksumAsset else {
      throw AppUpdateError.missingChecksumAsset
    }

    try await verifyChecksum(for: destinationURL, checksumAsset: checksumAsset)
    return AppDownloadedUpdate(archiveURL: destinationURL)
  }

  private func updatesDirectory() throws -> URL {
    try FileManager.default.createDirectory(
      at: Paths.updates,
      withIntermediateDirectories: true
    )
    return Paths.updates
  }

  private func verifyChecksum(
    for fileURL: URL, checksumAsset: GitHubReleaseAssetModel
  ) async throws {
    let (data, response) = try await dataLoader(URLRequest(url: checksumAsset.downloadURL))
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw AppUpdateError.checksumDownloadFailed
    }

    let checksumText = String(decoding: data, as: UTF8.self)
    guard let expectedChecksum = AppUpdateChecksumParser.expectedChecksum(from: checksumText)
    else {
      throw AppUpdateError.invalidChecksum
    }

    let fileData = try Data(contentsOf: fileURL)
    let actualChecksum = SHA256.hash(data: fileData)
      .map { String(format: "%02x", $0) }
      .joined()

    guard actualChecksum == expectedChecksum else {
      throw AppUpdateError.checksumMismatch
    }
  }
}

public struct AppUpdateRelease: Equatable, Sendable {
  public static let releasesPageURL = URL(string: "https://github.com/sukujgrg/thistle/releases")!

  public let version: String
  public let releaseURL: URL
  public let asset: GitHubReleaseAssetModel?
  public let checksumAsset: GitHubReleaseAssetModel?

  public init(
    version: String,
    releaseURL: URL,
    asset: GitHubReleaseAssetModel?,
    checksumAsset: GitHubReleaseAssetModel?
  ) {
    self.version = version
    self.releaseURL = releaseURL
    self.asset = asset
    self.checksumAsset = checksumAsset
  }

  public var isInstallable: Bool {
    asset != nil && checksumAsset != nil
  }
}

public struct AppDownloadedUpdate: Equatable, Sendable {
  public let archiveURL: URL

  public init(archiveURL: URL) {
    self.archiveURL = archiveURL
  }
}

public struct GitHubReleaseResponseModel: Decodable, Sendable {
  public let tagName: String
  public let htmlURL: URL
  public let assets: [GitHubReleaseAssetModel]

  public init(tagName: String, htmlURL: URL, assets: [GitHubReleaseAssetModel]) {
    self.tagName = tagName
    self.htmlURL = htmlURL
    self.assets = assets
  }

  public var primaryDownloadAsset: GitHubReleaseAssetModel? {
    assets.first { asset in
      asset.name.hasSuffix(".zip") && !asset.name.hasSuffix(".sha256")
    }
  }

  public var primaryChecksumAsset: GitHubReleaseAssetModel? {
    guard let primaryDownloadAsset else {
      return nil
    }

    return assets.first { asset in
      asset.name == "\(primaryDownloadAsset.name).sha256"
    }
      ?? assets.first { asset in
        asset.name.hasSuffix(".sha256")
      }
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case assets
  }
}

public struct GitHubReleaseAssetModel: Decodable, Equatable, Sendable {
  public let name: String
  public let downloadURL: URL

  public init(name: String, downloadURL: URL) {
    self.name = name
    self.downloadURL = downloadURL
  }

  enum CodingKeys: String, CodingKey {
    case name
    case downloadURL = "browser_download_url"
  }
}

public enum AppUpdateError: Error, LocalizedError, Equatable, Sendable {
  case updateCheckFailed
  case missingReleaseAsset
  case downloadFailed
  case missingChecksumAsset
  case checksumDownloadFailed
  case invalidChecksum
  case checksumMismatch

  public var errorDescription: String? {
    switch self {
    case .updateCheckFailed:
      "The update check failed."
    case .missingReleaseAsset:
      "The latest release does not include a supported zip download."
    case .downloadFailed:
      "The update download failed."
    case .missingChecksumAsset:
      "The latest release does not include a checksum file."
    case .checksumDownloadFailed:
      "The checksum download failed."
    case .invalidChecksum:
      "The checksum file could not be read."
    case .checksumMismatch:
      "The downloaded update did not match its checksum."
    }
  }
}

public enum AppUpdateChecksumParser {
  public static func expectedChecksum(from checksumText: String) -> String? {
    checksumText
      .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
      .first
      .map(String.init)?
      .lowercased()
  }
}

public struct AppVersionModel: Comparable, Equatable, Sendable {
  public let displayValue: String
  private let components: [Int]

  public init?(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutPrefix =
      trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
      ? String(trimmed.dropFirst())
      : trimmed
    let withoutBuildMetadata =
      withoutPrefix
      .split(separator: "+", maxSplits: 1)
      .first
      .map(String.init) ?? withoutPrefix
    let versionText =
      withoutBuildMetadata
      .split(separator: "-", maxSplits: 1)
      .first
      .map(String.init) ?? withoutBuildMetadata
    let rawComponents = versionText.split(separator: ".")
    let parsedComponents = rawComponents.compactMap { Int($0) }

    guard !parsedComponents.isEmpty,
      parsedComponents.count == rawComponents.count
    else {
      return nil
    }

    displayValue = withoutPrefix
    components = parsedComponents
  }

  public static func < (lhs: AppVersionModel, rhs: AppVersionModel) -> Bool {
    let maxCount = max(lhs.components.count, rhs.components.count)
    for index in 0..<maxCount {
      let leftValue = index < lhs.components.count ? lhs.components[index] : 0
      let rightValue = index < rhs.components.count ? rhs.components[index] : 0
      if leftValue != rightValue {
        return leftValue < rightValue
      }
    }
    return false
  }

  public static func == (lhs: AppVersionModel, rhs: AppVersionModel) -> Bool {
    !(lhs < rhs) && !(rhs < lhs)
  }
}
