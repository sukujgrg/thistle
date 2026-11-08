import Foundation

#if canImport(Darwin)
  import Darwin
#endif

/// Local Network privacy helpers (Apple TN3179).
///
/// Built-in engine traffic uses loopback and does not need these helpers.
/// Remote mode may still need Local Network when the URL targets a LAN host.
public enum LocalNetworkPrivacy {
  /// System Settings deep link for Privacy & Security > Local Network.
  public static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork"
  )!

  /// Whether reaching `url` can require the Local Network privilege on macOS.
  public static func urlRequiresPermission(_ url: URL) -> Bool {
    guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty
    else { return false }
    let normalized = host.lowercased()
    if normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
      || normalized == "[::1]"
    {
      return false
    }
    if normalized.hasSuffix(".local") || normalized.hasSuffix(".local.") {
      return true
    }
    if isIPv4Literal(normalized) {
      return isPrivateOrLinkLocalIPv4(normalized)
    }
    // Non-loopback DNS names may resolve to a local address; treat as requiring
    // Local Network so the user can grant access if macOS asks.
    return true
  }

  /// Best-effort trigger for the Local Network alert (TN3179).
  ///
  /// Connects UDP sockets to link-local IPv6 addresses without sending traffic.
  /// Use only when about to contact a URL that `urlRequiresPermission`.
  public static func triggerAlert() {
    #if os(macOS)
      for address in selectedLinkLocalIPv6Addresses() {
        let sock6 = socket(AF_INET6, SOCK_DGRAM, 0)
        guard sock6 >= 0 else { return }
        defer { close(sock6) }
        withUnsafePointer(to: address) { sa6 in
          sa6.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            _ = connect(sock6, sa, socklen_t(sa.pointee.sa_len))
          }
        }
      }
    #endif
  }

  private static func isIPv4Literal(_ host: String) -> Bool {
    host.split(separator: ".").count == 4
      && host.split(separator: ".").allSatisfy { UInt8($0) != nil }
  }

  private static func isPrivateOrLinkLocalIPv4(_ host: String) -> Bool {
    let parts = host.split(separator: ".").compactMap { UInt8($0) }
    guard parts.count == 4 else { return false }
    let a = parts[0]
    let b = parts[1]
    if a == 10 { return true }
    if a == 172 && (16...31).contains(b) { return true }
    if a == 192 && b == 168 { return true }
    if a == 169 && b == 254 { return true }
    return false
  }

  #if os(macOS)
    private static func selectedLinkLocalIPv6Addresses() -> [sockaddr_in6] {
      var addresses: [sockaddr_in6] = []
      var ifaddr: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return addresses }
      defer { freeifaddrs(ifaddr) }

      var cursor: UnsafeMutablePointer<ifaddrs>? = first
      while let iface = cursor {
        defer { cursor = iface.pointee.ifa_next }
        guard let sa = iface.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET6)
        else { continue }
        var sin6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
        let bytes = withUnsafeBytes(of: &sin6.sin6_addr) { Array($0) }
        // fe80::/10 link-local
        guard bytes.count >= 2, bytes[0] == 0xfe, (bytes[1] & 0xc0) == 0x80 else { continue }
        sin6.sin6_port = in_port_t(9).bigEndian  // discard protocol
        addresses.append(sin6)
      }
      return addresses
    }
  #endif
}
