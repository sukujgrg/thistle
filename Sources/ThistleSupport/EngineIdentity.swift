import Foundation

public enum EngineIdentity: Sendable {
  public static let appBundleIdentifier = "dev.thistle"
  public static let containerID = "thistle"
  /// Gotenberg listen port inside the guest.
  public static let guestPort = 3000
  /// Default host loopback port for the built-in API (Copy URL / health / converts).
  public static let hostAPIPort = 18_765
  /// Guest vsock port for the API bridge (kept clear of Containerization's 0x1000_0000 relays).
  public static let apiVsockPort: UInt32 = 18_765
  public static let guestForwarderResourceName = "vsock-tcp-forward"
  public static let guestForwarderGuestPath = "/usr/local/bin/vsock-tcp-forward"
  public static let guestForwarderMount = "/opt/thistle"
  public static let image = "docker.io/gotenberg/gotenberg:8"
  public static let initfs = "ghcr.io/apple/containerization/vminit:0.43.0"
  public static let cpus = 1
  public static let memoryMiB: UInt64 = 2048
  public static let xpcService = "dev.thistle.engine"
  public static let agentPlist = "dev.thistle.engine.plist"
  public static let developerTeamID = "E5N29VFW8T"
  public static let protocolVersion = 2
  public static let cacheSchema = 1
  public static let kernelVersion = "3.26.0"
  public static let idle: Duration = .seconds(15 * 60)
  public static let watchdog: Duration = .seconds(10)
  public static let recoverAttempts = 3

  public static var loopbackAPIURL: URL {
    loopbackAPIURL(port: hostAPIPort)
  }

  public static func loopbackAPIURL(port: Int) -> URL {
    URL(string: "http://127.0.0.1:\(port)")!
  }
}
