#if os(macOS) && arch(arm64)
  import Foundation
  import Testing
  import ThistleSupport
  @testable import ThistleMacOS

  @MainActor
  struct EngineAgentTests {
    @Test func launchAgentIdentifiesItsResponsibleApp() throws {
      let config = EngineAgent.configuration(
        helper: "/Applications/Thistle.app/Contents/MacOS/ThistleEngine",
        log: "/tmp/thistle-test.log", bundleIdentifier: "dev.thistle")
      #expect(config["AssociatedBundleIdentifiers"] as? [String] == ["dev.thistle"])
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

    @Test func permissionFailureOffersSettings() {
      let controller = EngineController(settings: EngineSettings())
      controller.status = .failed(EngineError.localNetworkAccessDenied.description)
      #expect(controller.needsLocalNetworkAccess)
      controller.status = .failed("An unrelated engine error")
      #expect(!controller.needsLocalNetworkAccess)
    }
  }
#endif
