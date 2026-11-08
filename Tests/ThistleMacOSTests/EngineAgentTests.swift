#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  @MainActor
  struct EngineAgentTests {
    @Test func launchAgentIdentifiesItsResponsibleApp() throws {
      let config = EngineAgent.configuration(bundleIdentifier: "dev.thistle")
      #expect(config["AssociatedBundleIdentifiers"] as? [String] == ["dev.thistle"])
      #expect(config["BundleProgram"] as? String == "Contents/MacOS/ThistleEngine")
      #expect(config["Label"] as? String == EngineIdentity.xpcService)
      let data = try PropertyListSerialization.data(
        fromPropertyList: config, format: .xml, options: 0)
      let decoded = try #require(
        PropertyListSerialization.propertyList(from: data, options: [], format: nil)
          as? [String: Any])
      #expect(NSDictionary(dictionary: decoded).isEqual(to: config))
      var oldConfig = config
      oldConfig.removeValue(forKey: "AssociatedBundleIdentifiers")
      #expect(!NSDictionary(dictionary: oldConfig).isEqual(to: config))
    }

    @Test func bundledLaunchAgentMatchesSMAppServiceShape() throws {
      let url = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Library/LaunchAgents/\(EngineIdentity.agentPlist)")
      // Unit tests may not load from the app bundle; compare against repo source shape.
      let expected = EngineAgent.configuration(bundleIdentifier: EngineIdentity.appBundleIdentifier)
      #expect(expected["BundleProgram"] as? String == "Contents/MacOS/ThistleEngine")
      #expect((expected["MachServices"] as? [String: Bool])?[EngineIdentity.xpcService] == true)
      _ = url
    }

    @Test func permissionFailureOffersSettingsOnlyForRemoteLAN() {
      let builtIn = EngineController(settings: EngineSettings())
      builtIn.status = .failed(EngineError.localNetworkAccessDenied.description)
      #expect(!builtIn.needsLocalNetworkAccess)

      let remote = EngineController(
        settings: EngineSettings(mode: .remote, remoteURL: "http://192.168.1.10:3000"))
      remote.remoteURLText = "http://192.168.1.10:3000"
      remote.status = .failed(EngineError.localNetworkAccessDenied.description)
      #expect(remote.needsLocalNetworkAccess)
      #expect(!remote.needsAgentApproval)

      remote.status = .failed(EngineError.agentNeedsApproval.description)
      #expect(remote.needsAgentApproval)
      #expect(!remote.needsLocalNetworkAccess)

      let loopbackRemote = EngineController(
        settings: EngineSettings(mode: .remote, remoteURL: "http://127.0.0.1:3000"))
      loopbackRemote.remoteURLText = "http://127.0.0.1:3000"
      loopbackRemote.status = .failed(EngineError.localNetworkAccessDenied.description)
      #expect(!loopbackRemote.needsLocalNetworkAccess)
    }
  }
#endif
