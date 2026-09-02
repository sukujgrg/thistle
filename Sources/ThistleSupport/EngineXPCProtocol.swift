import Foundation

@objc
public protocol EngineXPCProtocol: NSObjectProtocol {
  func fetchStatus(reply: @escaping @Sendable (Data?, String?) -> Void)
  func startEngine(reply: @escaping @Sendable (String?) -> Void)
  func stopEngine(reply: @escaping @Sendable (String?) -> Void)
  func restartEngine(reply: @escaping @Sendable (String?) -> Void)
  func refreshImage(reply: @escaping @Sendable (String?) -> Void)
  func resetEngine(reply: @escaping @Sendable (String?) -> Void)
  func clearLogs(reply: @escaping @Sendable (String?) -> Void)
  func submitJob(
    jobID: String, path: String, fieldsJSON: Data, filesJSON: Data,
    reply: @escaping @Sendable (Data?, String?) -> Void)
}
