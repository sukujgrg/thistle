#if os(macOS) && arch(arm64)

  import Foundation

  struct FormFileUpload: Equatable, Sendable {
    var field: String
    var url: URL
    /// Multipart filename when it must differ from the source file name (stamp assets, etc.).
    var filename: String?

    init(field: String, url: URL, filename: String? = nil) {
      self.field = field
      self.url = url
      self.filename = filename
    }
  }

#endif
