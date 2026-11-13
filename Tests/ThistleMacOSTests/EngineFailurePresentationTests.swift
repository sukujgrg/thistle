#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  struct EngineFailurePresentationTests {
    @Test func localNetworkDeniedOffersSettingsWhenRequired() {
      let presentation = EngineFailurePresentation.engine(
        message: EngineError.localNetworkAccessDenied.description,
        kind: .localNetworkDenied,
        usesRemote: true,
        needsLocalNetworkAccess: true
      )
      #expect(presentation.title == "Local network access blocked")
      #expect(presentation.primaryAction == .openLocalNetworkSettings)
      #expect(presentation.primaryTitle == "Open Local Network Settings")
      #expect(presentation.showsDetails)
      #expect(presentation.detail == EngineError.localNetworkAccessDenied.description)
    }

    @Test func agentApprovalOffersLoginItems() {
      let presentation = EngineFailurePresentation.engine(
        message: EngineError.agentNeedsApproval.description,
        kind: .agentNeedsApproval,
        usesRemote: false,
        needsLocalNetworkAccess: false
      )
      #expect(presentation.title == "Engine helper needs approval")
      #expect(presentation.primaryAction == .openLoginItems)
      #expect(presentation.primaryTitle == "Open Login Items")
    }

    @Test func genericBuiltInOffersTryAgain() {
      let presentation = EngineFailurePresentation.engine(
        message: EngineError.hostAPIPortInUse(18_765).description,
        kind: .generic,
        usesRemote: false,
        needsLocalNetworkAccess: false
      )
      #expect(presentation.title == "Couldn't start the engine")
      #expect(presentation.primaryAction == .tryAgain)
      #expect(presentation.primaryTitle == "Try Again")
      #expect(presentation.detail.contains("18765"))
    }

    @Test func genericRemoteOffersConnect() {
      let presentation = EngineFailurePresentation.engine(
        message: "Could not connect to Gotenberg: timed out",
        kind: .generic,
        usesRemote: true,
        needsLocalNetworkAccess: false
      )
      #expect(presentation.title == "Couldn't connect")
      #expect(presentation.primaryAction == .connect)
      #expect(presentation.primaryTitle == "Connect")
    }

    @Test func localNetworkDeniedWithoutPermissionGateFallsBackToConnect() {
      let presentation = EngineFailurePresentation.engine(
        message: EngineError.localNetworkAccessDenied.description,
        kind: .localNetworkDenied,
        usesRemote: true,
        needsLocalNetworkAccess: false
      )
      #expect(presentation.primaryAction == .connect)
      #expect(presentation.title == "Couldn't connect")
    }

    @Test func jobImportAndSaveTitlesStayPlain() {
      #expect(EngineFailurePresentation.job(message: "boom").title == "Conversion failed")
      #expect(EngineFailurePresentation.job(message: "boom").detail == "boom")
      #expect(
        EngineFailurePresentation.importFailure(message: "bad type").title
          == "Couldn't add that file")
      #expect(EngineFailurePresentation.saveFailure(message: "disk full").title == "Couldn't save")
    }
  }

  @MainActor
  struct EngineRecoveryChromeTests {
    @Test func showActivityDetailsOpensInspectorAndFocusesLog() {
      let controller = EngineController(settings: EngineSettings())
      #expect(!controller.inspectorPresented)
      #expect(!controller.focusActivityLog)
      controller.showActivityDetails()
      #expect(controller.inspectorPresented)
      #expect(controller.focusActivityLog)
    }

    @Test func presentationAlignsWithControllerPermissionGates() {
      let remote = EngineController(
        settings: EngineSettings(mode: .remote, remoteURL: "http://192.168.1.10:3000"))
      remote.remoteURLText = "http://192.168.1.10:3000"
      remote.status = .failed(
        message: EngineError.localNetworkAccessDenied.description, kind: .localNetworkDenied)
      let presentation = EngineFailurePresentation.engine(
        message: EngineError.localNetworkAccessDenied.description,
        kind: .localNetworkDenied,
        usesRemote: remote.usesRemote,
        needsLocalNetworkAccess: remote.needsLocalNetworkAccess
      )
      #expect(remote.needsLocalNetworkAccess)
      #expect(presentation.primaryAction == .openLocalNetworkSettings)
    }
  }
#endif
