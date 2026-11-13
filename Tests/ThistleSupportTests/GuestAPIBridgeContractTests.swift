import Foundation
import Testing

@testable import ThistleSupport

struct GuestAPIBridgeContractTests {
  @Test func hostAPIErrorsAreActionable() {
    let message = EngineError.hostAPIPortInUse(18_765).description
    #expect(message.contains("18765"))
    #expect(message.contains("Advanced settings"))
    #expect(message.contains("18766"))
    #expect(message.contains("28765"))
    #expect(EngineError.apiBridgeFailed("boom").description.contains("Local API bridge failed"))
    #expect(
      EngineError.guestForwarderFailed("timeout").description.contains("Guest API forwarder failed"))
    #expect(
      EngineError.guestForwarderMissing("/tmp/missing").description.contains("make guest-forwarder"))
  }

  @Test func builtInAPIURLNeverRequiresLocalNetwork() {
    #expect(!LocalNetworkPrivacy.urlRequiresPermission(EngineIdentity.loopbackAPIURL))
  }

  @Test func vsockPortStaysClearOfContainerizationRelays() {
    #expect(EngineIdentity.apiVsockPort < 0x1000_0000)
    #expect(EngineIdentity.apiVsockPort == UInt32(EngineIdentity.hostAPIPort))
  }

  @Test func watchdogRequiresConsecutiveHealthFailuresBeforeRecover() {
    #expect(EngineIdentity.healthFailureThreshold == 3)
    #expect(EngineIdentity.versionProbeAttempts >= 3)
  }
}
