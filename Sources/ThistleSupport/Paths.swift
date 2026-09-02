import Foundation

public enum Paths: Sendable {
  public static let appRoot: URL = {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("thistle")
  }()

  public static let kernelDirectory = appRoot.appendingPathComponent("kernel")
  public static let kernel = kernelDirectory.appendingPathComponent("vmlinux")
  public static let cacheDirectory = appRoot.appendingPathComponent("cache")
  public static let writable = appRoot.appendingPathComponent("containers/thistle/writable.ext4")
  public static let runtimeState = appRoot.appendingPathComponent("runtime.json")
  public static let initfs = appRoot.appendingPathComponent("initfs.ext4")
  public static let generation = appRoot.appendingPathComponent("engine-generation.json")
  public static let jobs = appRoot.appendingPathComponent("jobs")
  public static let instanceLock = appRoot.appendingPathComponent("instance.lock")
  public static let settings = appRoot.appendingPathComponent("settings.json")
  public static let engineLog = appRoot.appendingPathComponent("engine.log")
  public static let engineLogPrevious = appRoot.appendingPathComponent("engine.log.1")
  public static let updates = appRoot.appendingPathComponent("Updates")

  public static func rootfs(for image: String) -> URL {
    cacheDirectory.appendingPathComponent(rootfsName(for: image))
  }

  public static func rootfsName(for image: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
    let slug = String(image.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    return "\(slug).ext4"
  }

  public static func jobDirectory(_ id: String) -> URL {
    jobs.appendingPathComponent(id)
  }

  public static func clearJobs(keeping keep: URL? = nil) {
    OutputFile.clearDirectory(jobs, keeping: keep)
  }

  public static func ensureDirectories() throws {
    let fm = FileManager.default
    try fm.createDirectory(at: kernelDirectory, withIntermediateDirectories: true)
    try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    try fm.createDirectory(at: jobs, withIntermediateDirectories: true)
    try fm.createDirectory(
      at: writable.deletingLastPathComponent(), withIntermediateDirectories: true)
  }

  public static func resetCaches(keepingInstanceLock: Bool = true) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: appRoot.path(percentEncoded: false)) else { return }
    let items = try fm.contentsOfDirectory(
      at: appRoot, includingPropertiesForKeys: nil, options: [])
    let keep: Set<String> = {
      var names: Set<String> = [settings.lastPathComponent]
      if keepingInstanceLock {
        names.insert(instanceLock.lastPathComponent)
      }
      return names
    }()
    var firstError: Error?
    for item in items {
      if keep.contains(item.lastPathComponent) {
        continue
      }
      do {
        try fm.removeItem(at: item)
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }
    if let firstError {
      throw firstError
    }
  }
}

public struct RuntimeState: Codable, Sendable {
  public var baseURL: String

  public init(baseURL: String) {
    self.baseURL = baseURL
  }
}
