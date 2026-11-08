import Foundation
import Testing

@testable import ThistleSupport

struct LocalNetworkPrivacyTests {
  @Test func loopbackDoesNotRequirePermission() throws {
    #expect(!LocalNetworkPrivacy.urlRequiresPermission(URL(string: "http://127.0.0.1:18765")!))
    #expect(!LocalNetworkPrivacy.urlRequiresPermission(URL(string: "http://localhost:3000")!))
    #expect(!LocalNetworkPrivacy.urlRequiresPermission(URL(string: "http://[::1]:3000")!))
  }

  @Test func privateLANRequiresPermission() throws {
    #expect(LocalNetworkPrivacy.urlRequiresPermission(URL(string: "http://192.168.1.10:3000")!))
    #expect(LocalNetworkPrivacy.urlRequiresPermission(URL(string: "http://10.0.0.2:3000")!))
    #expect(LocalNetworkPrivacy.urlRequiresPermission(URL(string: "http://printer.local/api")!))
  }

  @Test func loopbackAPIURLUsesStablePort() {
    #expect(EngineIdentity.loopbackAPIURL.absoluteString == "http://127.0.0.1:18765")
    #expect(EngineIdentity.hostAPIPort == 18_765)
    #expect(EngineIdentity.apiVsockPort == 18_765)
    #expect(
      EngineIdentity.loopbackAPIURL(port: 18_766).absoluteString == "http://127.0.0.1:18766")
  }
}
