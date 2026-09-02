import Foundation

public enum EnginePhase: String, Sendable, Codable {
  case kernel
  case downloadingKernel
  case extractingKernel
  case pulling
  case unpacking
  case booting
  case waitingForAPI

  public var label: String {
    switch self {
    case .kernel: "Preparing kernel"
    case .downloadingKernel: "Downloading kernel"
    case .extractingKernel: "Extracting kernel"
    case .pulling: "Pulling image"
    case .unpacking: "Unpacking filesystem"
    case .booting: "Booting engine"
    case .waitingForAPI: "Waiting for API"
    }
  }
}

public struct EngineLogEntry: Identifiable, Equatable, Sendable, Codable {
  public static let retainedCount = 200

  public let id: UUID
  public let date: Date
  public let message: String

  public init(id: UUID = UUID(), date: Date = Date(), message: String) {
    self.id = id
    self.date = date
    self.message = message
  }

  public static func append(_ message: String, to logs: inout [EngineLogEntry]) {
    logs.append(EngineLogEntry(message: message))
    if logs.count > retainedCount {
      logs.removeFirst(logs.count - retainedCount)
    }
  }
}

public struct EngineStatusDTO: Codable, Sendable {
  public var protocolVersion: Int
  public var phase: String
  public var phaseLabel: String
  public var guestURL: String?
  public var failedMessage: String?
  public var logs: [EngineLogEntry]
  public var image: String
  public var initfs: String
  public var imageDigest: String?
  public var kernelVersion: String

  public init(
    protocolVersion: Int = EngineIdentity.protocolVersion,
    phase: String,
    phaseLabel: String,
    guestURL: String? = nil,
    failedMessage: String? = nil,
    logs: [EngineLogEntry] = [],
    image: String = EngineIdentity.image,
    initfs: String = EngineIdentity.initfs,
    imageDigest: String? = nil,
    kernelVersion: String = EngineIdentity.kernelVersion
  ) {
    self.protocolVersion = protocolVersion
    self.phase = phase
    self.phaseLabel = phaseLabel
    self.guestURL = guestURL
    self.failedMessage = failedMessage
    self.logs = logs
    self.image = image
    self.initfs = initfs
    self.imageDigest = imageDigest
    self.kernelVersion = kernelVersion
  }
}

public struct FileRefDTO: Codable, Sendable {
  public var field: String
  public var path: String
  // Multipart filename Gotenberg sees. Distinct from `path`, which may be a
  // unique staged copy such as 0-index.html.
  public var filename: String

  enum CodingKeys: String, CodingKey {
    case field, path, filename
  }

  public init(field: String, path: String, filename: String) {
    self.field = field
    self.path = path
    self.filename = filename
  }

  public var fileURL: URL {
    URL(fileURLWithPath: path)
  }

  public var multipartFilename: String {
    let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? fileURL.lastPathComponent : name
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    field = try container.decode(String.self, forKey: .field)
    path = try container.decode(String.self, forKey: .path)
    filename =
      try container.decodeIfPresent(String.self, forKey: .filename)
      ?? URL(fileURLWithPath: path).lastPathComponent
  }
}

public struct JobResultDTO: Codable, Sendable {
  public var jsonPreview: String?
  public var outputPath: String?
  public var suggestedExtension: String

  public init(jsonPreview: String? = nil, outputPath: String? = nil, suggestedExtension: String) {
    self.jsonPreview = jsonPreview
    self.outputPath = outputPath
    self.suggestedExtension = suggestedExtension
  }
}

public struct EngineGeneration: Codable, Sendable {
  public var schema: Int
  public var kernelVersion: String
  public var initfs: String
  public var image: String
  public var imageDigest: String
  public var unpackedDigest: String

  public init(
    schema: Int, kernelVersion: String, initfs: String, image: String, imageDigest: String,
    unpackedDigest: String
  ) {
    self.schema = schema
    self.kernelVersion = kernelVersion
    self.initfs = initfs
    self.image = image
    self.imageDigest = imageDigest
    self.unpackedDigest = unpackedDigest
  }

  public static func load() -> EngineGeneration? {
    guard let data = try? Data(contentsOf: Paths.generation) else { return nil }
    return try? JSONDecoder().decode(EngineGeneration.self, from: data)
  }

  public func save() throws {
    try JSONEncoder().encode(self).write(to: Paths.generation, options: .atomic)
  }
}
