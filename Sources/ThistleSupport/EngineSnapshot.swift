import Foundation

public struct EngineSnapshot: Sendable {
  public var image: String
  public var initfs: String
  public var containerID: String
  public var cpus: Int
  public var memoryMiB: UInt64
  public var guestURL: String?
  public var kernelPath: URL
  public var kernelPresent: Bool
  public var kernelSize: Int64?
  public var rootfsPath: URL
  public var rootfsPresent: Bool
  public var rootfsSize: Int64?
  public var writablePresent: Bool
  public var storePath: URL
  public var storeSize: Int64?
  public var imageDigest: String?

  public static func placeholder(guestURL: String?, imageDigest: String? = nil) -> EngineSnapshot {
    current(guestURL: guestURL, imageDigest: imageDigest, measureStore: false)
  }

  @concurrent
  public static func load(guestURL: String?, imageDigest: String? = nil) async -> EngineSnapshot {
    current(guestURL: guestURL, imageDigest: imageDigest, measureStore: true)
  }

  private static func current(guestURL: String?, imageDigest: String?, measureStore: Bool)
    -> EngineSnapshot
  {
    let image = EngineIdentity.image
    let kernel = Paths.kernel
    let rootfs = Paths.rootfs(for: image)
    return EngineSnapshot(
      image: image,
      initfs: EngineIdentity.initfs,
      containerID: EngineIdentity.containerID,
      cpus: EngineIdentity.cpus,
      memoryMiB: EngineIdentity.memoryMiB,
      guestURL: guestURL,
      kernelPath: kernel,
      kernelPresent: exists(kernel),
      kernelSize: fileSize(kernel),
      rootfsPath: rootfs,
      rootfsPresent: exists(rootfs),
      rootfsSize: fileSize(rootfs),
      writablePresent: exists(Paths.writable),
      storePath: Paths.appRoot,
      storeSize: measureStore ? directorySize(Paths.appRoot) : nil,
      imageDigest: imageDigest
    )
  }

  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }

  private static let sizeKeys: Set<URLResourceKey> = [
    .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
  ]

  // On-disk blocks, matching `du`. Logical size is larger for sparse ext4 images.
  private static func fileSize(_ url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: sizeKeys)
    guard values?.isRegularFile == true else { return nil }
    if let allocated = values?.totalFileAllocatedSize {
      return Int64(allocated)
    }
    return Int64(values?.fileSize ?? 0)
  }

  private static func directorySize(_ url: URL) -> Int64? {
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: Array(sizeKeys),
        options: []
      )
    else {
      return nil
    }
    var total: Int64 = 0
    var found = false
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: sizeKeys)
      guard values?.isRegularFile == true else { continue }
      found = true
      if let allocated = values?.totalFileAllocatedSize {
        total += Int64(allocated)
      } else {
        total += Int64(values?.fileSize ?? 0)
      }
    }
    return found ? total : nil
  }
}

public enum ByteFormat {
  public static func string(_ bytes: Int64?) -> String {
    guard let bytes else { return "—" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  public static func path(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    var home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    while home.hasSuffix("/") && home != "/" {
      home.removeLast()
    }
    if path == home {
      return "~"
    }
    if path.hasPrefix(home + "/") {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }

  // Unquoted path for a shell: ~/Library/Application\ Support/...
  public static func shellPath(_ url: URL) -> String {
    let display = path(url)
    if display == "~" {
      return "~"
    }
    if display.hasPrefix("~/") {
      return "~/" + escape(String(display.dropFirst(2)))
    }
    return escape(display)
  }

  private static func escape(_ value: String) -> String {
    var out = ""
    out.reserveCapacity(value.count)
    for character in value {
      if needsEscape(character) {
        out.append("\\")
      }
      out.append(character)
    }
    return out
  }

  private static func needsEscape(_ character: Character) -> Bool {
    if character.isWhitespace { return true }
    switch character {
    case "\\", "'", "\"", "$", "`", "!", "*", "?", "[", "]", "(", ")", "{", "}",
      ";", "&", "|", "<", ">", "#", "~":
      return true
    default:
      return false
    }
  }
}
