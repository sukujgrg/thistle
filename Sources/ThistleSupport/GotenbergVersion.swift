import Foundation

/// Thistle 1.0 speaks Gotenberg 9 only.
public enum GotenbergRequirement {
  public static let minimumMajor = 9

  /// When the engine reports a parseable version, reject anything below major 9.
  /// Unknown / unparseable versions stay allowed so custom builds without `/version` still work.
  public static func issue(version: String?) -> String? {
    guard let version, let current = AppVersionModel(version) else { return nil }
    guard current.major < minimumMajor else { return nil }
    return
      "Thistle 1.0 requires Gotenberg \(minimumMajor) or later. Connected engine: \(version)."
  }
}

public struct GotenbergRelease: Equatable, Sendable {
  public let version: String
  public var url: URL {
    URL(string: "https://github.com/gotenberg/gotenberg/releases/tag/v\(version)")!
  }
}

public actor GotenbergReleaseChecker {
  private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  public init(session: URLSession = .shared) {
    dataLoader = { try await session.data(for: $0) }
  }

  init(dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
    self.dataLoader = dataLoader
  }

  public func latest() async throws -> GotenbergRelease {
    let url = URL(string: "https://api.github.com/repos/gotenberg/gotenberg/releases/latest")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("thistle", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await dataLoader(request)
    struct Release: Decodable {
      let tag_name: String
      let prerelease: Bool
      let draft: Bool
    }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      let release = try? JSONDecoder().decode(Release.self, from: data),
      !release.prerelease, !release.draft,
      let version = AppVersionModel(release.tag_name)
    else {
      throw EngineError.operationFailed(
        "Could not check the latest Gotenberg release. Try again later.")
    }
    return GotenbergRelease(version: version.displayValue)
  }
}
