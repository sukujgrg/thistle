import Foundation

/// Coarse engine lifecycle shared by the helper, XPC DTO, and app UI.
public enum EngineLifecyclePhase: String, Codable, Sendable, Equatable {
  case idle
  case starting
  case running
  case failed
}

/// Typed failure reasons for settings CTAs. Generic covers everything else.
public enum EngineFailureKind: String, Codable, Sendable, Equatable {
  case generic
  case localNetworkDenied
  case agentNeedsApproval

  public static func from(_ error: Error) -> EngineFailureKind {
    let normalized = NetworkFailure.normalized(error)
    if let engineError = normalized as? EngineError {
      switch engineError {
      case .localNetworkAccessDenied: return .localNetworkDenied
      case .agentNeedsApproval: return .agentNeedsApproval
      default: return .generic
      }
    }
    return infer(from: EngineError.message(for: error))
  }

  /// Fallback when only a failure string is available (polled DTO).
  public static func infer(from message: String) -> EngineFailureKind {
    if message.contains(EngineError.localNetworkAccessDenied.description) {
      return .localNetworkDenied
    }
    if message.contains(EngineError.agentNeedsApproval.description) {
      return .agentNeedsApproval
    }
    return .generic
  }
}
