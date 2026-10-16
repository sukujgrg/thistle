import Foundation

public enum GotenbergCompatibility {
  public static func minimumVersion(forField name: String) -> String? {
    switch name {
    case "optimizeImages", "imageQuality", "selector", "titleBookmarks": "8.36.0"
    case "ownerPassword", "allowPrinting", "allowCopying", "allowModifying", "allowAnnotating",
      "allowFillingForms", "allowAssembling", "facturxConformanceLevel", "facturxDocumentType",
      "facturxVersion":
      "8.34.0"
    case "deviceScaleFactor": "8.33.0"
    case "skipNetworkAlmostIdleEvent", "initialView", "initialPage", "magnification", "zoom",
      "pageLayout", "firstPageOnLeft", "resizeWindowToInitialPage", "centerWindow",
      "openInFullScreenMode", "displayPDFDocumentTitle", "hideViewerMenubar", "hideViewerToolbar",
      "hideViewerWindowControls", "useTransitionEffects", "openBookmarkLevels":
      "8.29.0"
    case "rotateAngle", "rotatePages", "autoIndexBookmarks": "8.28.0"
    case let key
    where key.hasPrefix("watermark") || key.hasPrefix("stamp") || key.hasPrefix("nativeWatermark")
      || key == "nativeTiledWatermarkText":
      "8.28.0"
    case "emulatedMediaFeatures": "8.27.0"
    case "waitForSelector", "ignoreResourceHttpStatusDomains": "8.26.0"
    case "userPassword", "embedsMetadata": "8.25.0"
    default: nil
    }
  }

  public static func minimumVersion(forRoute path: String) -> String? {
    switch path {
    case "/forms/pdfengines/optimize": "8.36.0"
    case "/forms/pdfengines/factur-x": "8.34.0"
    case "/forms/pdfengines/rotate", "/forms/pdfengines/watermark", "/forms/pdfengines/stamp",
      "/forms/pdfengines/bookmarks/read", "/forms/pdfengines/bookmarks/write":
      "8.28.0"
    case "/forms/pdfengines/encrypt", "/forms/pdfengines/embed": "8.25.0"
    default: nil
    }
  }

  public static func issue(version: String?, path: String, fields: [MultipartField]) -> String? {
    guard let version, let current = AppVersionModel(version) else { return nil }
    if let minimum = minimumVersion(forRoute: path), current < AppVersionModel(minimum)! {
      return "This action requires Gotenberg \(minimum) or later. Connected engine: \(version)."
    }
    for field in fields {
      if let minimum = minimumVersion(forField: field.name), current < AppVersionModel(minimum)! {
        return "\(field.name) requires Gotenberg \(minimum) or later. Connected engine: \(version)."
      }
    }
    for prefix in ["watermark", "stamp"]
    where fields.filter({ $0.name == "\(prefix)Source" }).count > 1 {
      if current < AppVersionModel("8.36.0")! {
        return
          "Multiple \(prefix)s require Gotenberg 8.36.0 or later. Connected engine: \(version)."
      }
    }
    return nil
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
