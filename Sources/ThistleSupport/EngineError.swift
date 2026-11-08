import Foundation

public enum EngineError: Error, Sendable, CustomStringConvertible {
  case kernelNotFound(String)
  case kernelDownloadFailed(String)
  case kernelExtractFailed(String)
  case notAppleSilicon
  case missingNetworkInterface
  case healthCheckFailed(String)
  case localNetworkAccessDenied
  case convertFailed(status: Int, body: String)
  case notRunning
  case agentUnavailable(String)
  case operationFailed(String)
  case agentNeedsApproval
  case protocolMismatch(Int)
  case invalidEngineURL(String)
  case stagingFailed(String)
  case hostAPIPortInUse(Int)
  case apiBridgeFailed(String)
  case guestForwarderFailed(String)
  case guestForwarderMissing(String)

  public var description: String {
    switch self {
    case .kernelNotFound(let path):
      "Linux kernel not found at \(path)"
    case .kernelDownloadFailed(let reason):
      "Kernel download failed: \(reason)"
    case .kernelExtractFailed(let reason):
      "Kernel extract failed: \(reason)"
    case .notAppleSilicon:
      "Thistle requires Apple silicon"
    case .missingNetworkInterface:
      "container has no IPv4 interface; check macOS 26 vmnet support"
    case .healthCheckFailed(let reason):
      "Engine did not become ready: \(reason)"
    case .localNetworkAccessDenied:
      "macOS blocked local-network access. Allow Thistle in System Settings > Privacy & Security > Local Network, then try again."
    case .convertFailed(let status, let body):
      "request failed (HTTP \(status)): \(body)"
    case .notRunning:
      "Engine is not running. Start the engine first."
    case .agentUnavailable(let reason):
      "Engine helper is unavailable: \(reason)"
    case .operationFailed(let reason):
      reason
    case .agentNeedsApproval:
      "Enable Thistle Engine in System Settings > General > Login Items, then Start Engine again."
    case .protocolMismatch(let version):
      "Engine helper protocol \(version) does not match the app. Quit both, rebuild, and start again."
    case .invalidEngineURL(let reason):
      "Custom Gotenberg URL is invalid: \(reason)"
    case .stagingFailed(let reason):
      reason
    case .hostAPIPortInUse(let port):
      "Local API port \(port) is already in use. Choose another port in Advanced settings (try 18766, 18767, or 28765), then Start Engine again."
    case .apiBridgeFailed(let reason):
      "Local API bridge failed: \(reason)"
    case .guestForwarderFailed(let reason):
      "Guest API forwarder failed: \(reason)"
    case .guestForwarderMissing(let path):
      "Guest API forwarder is missing at \(path). Run make guest-forwarder, then rebuild the app."
    }
  }

  public static func message(for error: Error) -> String {
    (NetworkFailure.normalized(error) as? EngineError)?.description ?? error.localizedDescription
  }
}
