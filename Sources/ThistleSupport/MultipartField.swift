import Foundation

/// An ordered multipart field. Names may repeat (for example, one set per stamp).
public struct MultipartField: Codable, Equatable, Sendable {
  public var name: String
  public var value: String

  public init(_ name: String, _ value: String) {
    self.name = name
    self.value = value
  }
}

extension Array where Element == MultipartField {
  public func firstValue(for name: String) -> String? {
    first { $0.name == name }?.value
  }
}
