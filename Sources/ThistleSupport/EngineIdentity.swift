import Foundation

public enum EngineIdentity: Sendable {
  public static let containerID = "thistle"
  public static let guestPort = 3000
  public static let image = "docker.io/gotenberg/gotenberg:8"
  public static let initfs = "ghcr.io/apple/containerization/vminit:0.43.0"
  public static let cpus = 1
  public static let memoryMiB: UInt64 = 2048
  public static let xpcService = "dev.thistle.engine"
  public static let agentPlist = "dev.thistle.engine.plist"
  public static let developerTeamID = "E5N29VFW8T"
  public static let protocolVersion = 1
  public static let cacheSchema = 1
  public static let kernelVersion = "3.26.0"
  public static let idle: Duration = .seconds(15 * 60)
  public static let watchdog: Duration = .seconds(10)
  public static let recoverAttempts = 3
}
