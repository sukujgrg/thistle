import Foundation

public enum EngineError: Error, Sendable, CustomStringConvertible {
  case kernelNotFound(String)
  case kernelDownloadFailed(String)
  case kernelExtractFailed(String)
  case notAppleSilicon
  case missingNetworkInterface
  case healthCheckFailed(String)
  case convertFailed(status: Int, body: String)
  case notRunning
  case agentUnavailable(String)
  case operationFailed(String)
  case agentNeedsApproval
  case protocolMismatch(Int)
  case invalidEngineURL(String)
  case stagingFailed(String)

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
    }
  }

  public static func message(for error: Error) -> String {
    (error as? EngineError)?.description ?? error.localizedDescription
  }
}
