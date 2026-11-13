#if os(macOS) && arch(arm64)

  import Foundation

  import ThistleSupport

  /// Maps engine failure state to plain-language chrome. UI stays dumb and tests cover this map.
  struct EngineFailurePresentation: Equatable, Sendable {
    enum PrimaryAction: Equatable, Sendable {
      case openLocalNetworkSettings
      case openLoginItems
      case tryAgain
      case connect
    }

    let title: String
    let detail: String
    let primaryAction: PrimaryAction
    let showsDetails: Bool

    var primaryTitle: String {
      switch primaryAction {
      case .openLocalNetworkSettings: "Open Local Network Settings"
      case .openLoginItems: "Open Login Items"
      case .tryAgain: "Try Again"
      case .connect: "Connect"
      }
    }

    static func engine(
      message: String,
      kind: EngineFailureKind,
      usesRemote: Bool,
      needsLocalNetworkAccess: Bool
    ) -> EngineFailurePresentation {
      let action: PrimaryAction
      let title: String
      switch kind {
      case .localNetworkDenied where needsLocalNetworkAccess:
        action = .openLocalNetworkSettings
        title = "Local network access blocked"
      case .agentNeedsApproval:
        action = .openLoginItems
        title = "Engine helper needs approval"
      case .localNetworkDenied, .generic:
        if usesRemote {
          action = .connect
          title = "Couldn't connect"
        } else {
          action = .tryAgain
          title = "Couldn't start the engine"
        }
      }
      return EngineFailurePresentation(
        title: title,
        detail: message,
        primaryAction: action,
        showsDetails: true
      )
    }

    static func job(message: String) -> (title: String, detail: String) {
      ("Conversion failed", message)
    }

    static func importFailure(message: String) -> (title: String, detail: String) {
      ("Couldn't add that file", message)
    }

    static func saveFailure(message: String) -> (title: String, detail: String) {
      ("Couldn't save", message)
    }
  }

#endif
