import Foundation
import Network

public enum NetworkFailure {
  public static func normalized(_ error: Error) -> Error {
    isLocalNetworkDenied(error) ? EngineError.localNetworkAccessDenied : error
  }

  public static func isLocalNetworkDenied(_ error: Error) -> Bool {
    let root = error as NSError
    guard root.domain == NSURLErrorDomain,
      root.code == URLError.notConnectedToInternet.rawValue
    else { return false }
    var current: NSError? = root
    for _ in 0..<4 {
      guard let item = current else { break }
      for value in item.userInfo.values {
        if let path = value as? NWPath, path.unsatisfiedReason == .localNetworkDenied {
          return true
        }
        // CFNetwork can expose an opaque path object rather than NWPath. Its
        // diagnostic description distinguishes this policy denial from offline.
        let detail = String(describing: value).lowercased()
        if detail.contains("unsatisfied"), detail.contains("local network prohibited") {
          return true
        }
      }
      current = item.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return false
  }
}
