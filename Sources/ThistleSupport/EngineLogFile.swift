import Darwin
import Foundation

// Caps engine.log at 1 MB. The helper owns stdout/stderr so launchd
// cannot keep appending to a renamed inode after a rotate.
public enum EngineLogFile {
  public static let maxByteCount = 1_048_576

  private static let lock = NSLock()

  public static func install() {
    try? FileManager.default.createDirectory(
      at: Paths.appRoot, withIntermediateDirectories: true)
    lock.lock()
    defer { lock.unlock() }
    if fileSizeLocked() > maxByteCount {
      rotateLocked()
    } else {
      reopenLocked()
    }
  }

  public static func rotateIfNeeded() {
    lock.lock()
    defer { lock.unlock() }
    fflush(stdout)
    fflush(stderr)
    guard fileSizeLocked() >= maxByteCount else { return }
    rotateLocked()
  }

  public static func clear() {
    lock.lock()
    defer { lock.unlock() }
    removeFiles()
    reopenLocked()
  }

  public static func removeFiles() {
    let fm = FileManager.default
    try? fm.removeItem(at: Paths.engineLogPrevious)
    try? fm.removeItem(at: Paths.engineLog)
  }

  private static func rotateLocked() {
    fflush(stdout)
    fflush(stderr)
    let fm = FileManager.default
    let current = Paths.engineLog
    let previous = Paths.engineLogPrevious
    let size = fileSizeLocked()
    try? fm.removeItem(at: previous)
    if size > maxByteCount {
      copyTail(from: current, to: previous, maxBytes: maxByteCount)
      try? fm.removeItem(at: current)
    } else if size > 0 {
      try? fm.moveItem(at: current, to: previous)
    }
    reopenLocked()
  }

  private static func reopenLocked() {
    let path = Paths.engineLog.path(percentEncoded: false)
    let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    guard fd >= 0 else { return }
    dup2(fd, STDOUT_FILENO)
    dup2(fd, STDERR_FILENO)
    if fd != STDOUT_FILENO && fd != STDERR_FILENO {
      close(fd)
    }
    setlinebuf(stdout)
    setlinebuf(stderr)
  }

  private static func fileSizeLocked() -> Int {
    let path = Paths.engineLog.path(percentEncoded: false)
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
      let size = attrs[.size] as? NSNumber
    else {
      return 0
    }
    return size.intValue
  }

  private static func copyTail(from source: URL, to destination: URL, maxBytes: Int) {
    guard let handle = try? FileHandle(forReadingFrom: source) else { return }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let keep = UInt64(maxBytes)
    if size > keep {
      try? handle.seek(toOffset: size - keep)
    } else {
      try? handle.seek(toOffset: 0)
    }
    guard let data = try? handle.readToEnd() else { return }
    try? data.write(to: destination, options: .atomic)
  }
}
