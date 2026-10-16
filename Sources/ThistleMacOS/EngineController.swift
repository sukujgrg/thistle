#if os(macOS) && arch(arm64)

  import AppKit
  import Foundation
  import Observation
  import UniformTypeIdentifiers

  import ThistleSupport

  @MainActor
  @Observable
  final class EngineController {
    enum Status: Equatable {
      case idle
      case starting(String)
      case running(String)
      case failed(String)
    }

    enum JobStatus: Equatable {
      case idle
      case working(String)
      case succeeded(String)
      case failed(String)
    }

    var status: Status = .idle
    var jobStatus: JobStatus = .idle
    var jsonPreview: String?
    var lastSuggestedName = ""
    var resultActionID: String?
    var resultSaved = false
    var saveError: String?
    var logs: [EngineLogEntry] = []
    var imageDigest: String?
    var settings: EngineSettings
    var remoteURLText: String
    var remoteCredentials = RemoteCredentials()
    var gotenbergVersion: String?
    var latestGotenbergRelease: GotenbergRelease?
    var checkingEngineUpdate = false
    var engineUpdateError: String?
    var inspectorPresented = false
    var confirmReset = false
    private static let lastSaveDirectoryKey = "lastSaveDirectory"

    private let client = EngineXPCClient()
    private let http = GotenbergClient()
    private let releaseChecker = GotenbergReleaseChecker()
    private var appliedRemoteCredentials = RemoteCredentials()
    private var credentialURL: URL?
    private var credentialLoadError: String?
    private var remoteConnectionID = UUID()
    private var pollTask: Task<Void, Never>?
    private var remoteWasReachable: Bool?
    private var unsavedJobDirectory: URL?
    private var suggestedSaveDirectory: URL?
    private var lastSaveDirectory: URL?

    init(settings loaded: EngineSettings = .load()) {
      settings = loaded
      remoteURLText = loaded.remoteURL
      if let url = try? EngineSettings.parseURL(loaded.remoteURL) {
        credentialURL = url
        do {
          remoteCredentials = try RemoteCredentialStore.load(for: url)
          appliedRemoteCredentials = remoteCredentials
        } catch {
          credentialLoadError = EngineError.message(for: error)
        }
      }
      if let path = UserDefaults.standard.string(forKey: Self.lastSaveDirectoryKey) {
        lastSaveDirectory = URL(fileURLWithPath: path)
      }
    }

    var canSaveResult: Bool {
      if jsonPreview != nil { return true }
      if case .succeeded = jobStatus { return true }
      return false
    }

    var isStarting: Bool {
      if case .starting = status { return true }
      return false
    }

    var isRunning: Bool {
      if case .running = status { return true }
      return false
    }

    var isWorking: Bool {
      if case .working = jobStatus { return true }
      return false
    }

    var usesRemote: Bool { settings.usesRemote }

    var needsLocalNetworkAccess: Bool {
      guard case .failed(let message) = status else { return false }
      return message.contains(EngineError.localNetworkAccessDenied.description)
    }

    var canManageVM: Bool { !usesRemote }

    var hasUnappliedRemoteURL: Bool {
      guard usesRemote else { return false }
      return remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines) != settings.remoteURL
        || remoteCredentials != appliedRemoteCredentials
    }

    var highlightsUnappliedRemoteURL: Bool {
      guard hasUnappliedRemoteURL else { return false }
      if case .failed = status { return false }
      return true
    }

    var remoteNeedsConnection: Bool {
      usesRemote && (!isRunning || hasUnappliedRemoteURL)
    }

    var canSubmitJobs: Bool {
      !usesRemote || !remoteNeedsConnection
    }

    var baseURL: URL? {
      if usesRemote {
        guard !remoteNeedsConnection else { return nil }
        return settings.apiURL
      }
      guard case .running(let value) = status else { return nil }
      return URL(string: value)
    }

    func connect() {
      guard pollTask == nil else { return }
      pollTask = Task { await pollLoop() }
    }

    func setMode(_ mode: EngineMode) async {
      if mode == settings.mode { return }
      if mode == .remote {
        status = .starting("Stopping built-in engine")
        do {
          try await client.stopIfLoaded()
        } catch {
          applyError(error)
          return
        }
      }
      settings.mode = mode
      remoteConnectionID = UUID()
      persistSettings()
      logs = []
      imageDigest = nil
      gotenbergVersion = nil
      remoteWasReachable = nil
      if mode == .remote {
        status = .idle
        await refreshRemote(connecting: false)
      } else {
        status = .idle
        await refreshStatus()
      }
    }

    func applyRemoteURL() async {
      if !usesRemote {
        await setMode(.remote)
        guard usesRemote else { return }
      }
      do {
        let url = try EngineSettings.parseURL(remoteURLText)
        // Changing only the URL must not carry saved credentials to a different API.
        if url != credentialURL, remoteCredentials == appliedRemoteCredentials {
          remoteCredentials = try RemoteCredentialStore.load(for: url)
        }
        _ = try remoteCredentials.authorizationHeader()
        try RemoteCredentialStore.save(remoteCredentials, for: url)
        var nextSettings = settings
        nextSettings.remoteURL = url.absoluteString
        try nextSettings.save()
        settings = nextSettings
        remoteConnectionID = UUID()
        appliedRemoteCredentials = remoteCredentials
        credentialURL = url
        credentialLoadError = nil
        remoteURLText = url.absoluteString
        gotenbergVersion = nil
        remoteWasReachable = nil
        status = .starting("Connecting")
        await refreshRemote(connecting: true)
      } catch {
        applyError(error)
      }
    }

    func start() async {
      if usesRemote {
        await applyRemoteURL()
        return
      }
      inspectorPresented = true
      status = .starting("Starting engine")
      do {
        try client.connect()
        try await client.start()
        await refreshStatus()
      } catch {
        applyError(error)
      }
    }

    func stop() async {
      if usesRemote { return }
      status = .starting("Stopping engine")
      do {
        try client.connect()
        try await client.stop()
        await refreshStatus()
      } catch {
        applyError(error)
      }
    }

    func restart() async {
      guard canManageVM else { return }
      inspectorPresented = true
      status = .starting("Restarting engine")
      do {
        try client.connect()
        try await client.restart()
        await refreshStatus()
      } catch {
        applyError(error)
      }
    }

    func refreshImage() async {
      guard canManageVM else { return }
      inspectorPresented = true
      status = .starting("Refreshing image")
      do {
        try client.connect()
        try await client.refreshImage()
        await refreshStatus()
      } catch {
        applyError(error)
      }
    }

    func resetEngine() async {
      guard canManageVM else { return }
      inspectorPresented = true
      status = .starting("Resetting engine")
      do {
        try client.connect()
        try await client.reset()
        resetJob()
        await refreshStatus()
      } catch {
        applyError(error)
      }
    }

    func prepareForTermination() {
      resetJob()
      Paths.clearJobs()
    }

    func prepareForUpdate() async {
      do {
        try await client.stopIfLoaded()
      } catch {
        // The helper is still unloaded below so relaunch cannot reuse it.
      }
      EngineAgent.unload()
    }

    func resetJob() {
      discardUnsavedResult()
      jobStatus = .idle
      jsonPreview = nil
      lastSuggestedName = ""
      resultActionID = nil
      resultSaved = false
      saveError = nil
      suggestedSaveDirectory = nil
    }

    func submit(
      action: ConvertAction, fields: [MultipartField], files: [(field: String, url: URL)],
      suggestedName: String, saveDirectory: URL? = nil
    ) async {
      discardUnsavedResult()
      jobStatus = .working(action.title)
      jsonPreview = nil
      lastSuggestedName = suggestedName
      resultActionID = action.id
      resultSaved = false
      saveError = nil
      suggestedSaveDirectory = saveDirectory
      let jobID = UUID().uuidString
      do {
        if let issue = compatibilityIssue(action: action, fields: fields) {
          throw EngineError.operationFailed(issue)
        }
        if usesRemote {
          guard canSubmitJobs else {
            throw EngineError.invalidEngineURL(
              "connect the current URL before running an action")
          }
          try await submitRemote(
            jobID: jobID, action: action, fields: fields, files: files,
            suggestedName: suggestedName)
        } else {
          try client.connect()
          let staged = try Self.stageFiles(
            jobID: jobID, action: action, fields: fields, files: files)
          let result = try await client.submit(
            jobID: jobID, path: action.path, fields: fields, files: staged)
          await refreshStatus()
          try finishJob(result: result, jobID: jobID, suggestedName: suggestedName)
        }
      } catch {
        try? FileManager.default.removeItem(at: Paths.jobDirectory(jobID))
        jobStatus = .failed(EngineError.message(for: error))
      }
    }

    private func submitRemote(
      jobID: String, action: ConvertAction, fields: [MultipartField],
      files: [(field: String, url: URL)],
      suggestedName: String
    ) async throws {
      let url = try EngineSettings.parseURL(settings.remoteURL)
      let staged = try Self.stageFiles(jobID: jobID, action: action, fields: fields, files: files)
      let trace = HTTPTrace()
      let response: GotenbergClient.Response
      do {
        response = try await http.submit(
          baseURL: url, path: action.path, fields: fields, files: staged,
          credentials: appliedRemoteCredentials, trace: trace)
      } catch {
        for line in trace.snapshot() {
          noteRemote(line)
        }
        noteRemote(EngineError.message(for: error))
        throw error
      }
      for line in trace.snapshot() {
        noteRemote(line)
      }
      try finishJob(
        result: response.jobResult(jobID: jobID), jobID: jobID, suggestedName: suggestedName)
    }

    private func finishJob(result: JobResultDTO, jobID: String, suggestedName: String) throws {
      jsonPreview = result.jsonPreview
      if result.jsonPreview != nil {
        jobStatus = .idle
        try? FileManager.default.removeItem(at: Paths.jobDirectory(jobID))
        return
      }
      guard let outputPath = result.outputPath else {
        throw EngineError.operationFailed("Conversion produced no output")
      }
      let jobDirectory = Paths.jobDirectory(jobID)
      let source = URL(fileURLWithPath: outputPath)
      let named = jobDirectory.appendingPathComponent(
        OutputFile.filename(basename: suggestedName, ext: result.suggestedExtension))
      try OutputFile.place(source, at: named, moving: true)
      unsavedJobDirectory = jobDirectory
      resultSaved = false
      jobStatus = .succeeded(named.path(percentEncoded: false))
    }

    func saveCurrentResult(defaultJSONName: String = "") async {
      if jsonPreview != nil {
        await saveJSONPreview(defaultName: defaultJSONName)
      } else {
        await saveResult()
      }
    }

    func saveResult() async {
      guard case .succeeded(let path) = jobStatus else { return }
      let source = URL(fileURLWithPath: path)
      let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension
      saveError = nil
      guard
        let output = await Self.askSave(
          basename: source.deletingPathExtension().lastPathComponent,
          type: Self.utType(for: ext),
          directory: defaultSaveDirectory()
        )
      else {
        return
      }
      do {
        try OutputFile.place(source, at: output, moving: !resultSaved)
        rememberSaveDirectory(output)
        let cleanup = !resultSaved
        resultSaved = true
        jobStatus = .succeeded(output.path(percentEncoded: false))
        if cleanup {
          discardUnsavedJobDirectoryKeepingResult()
        }
      } catch {
        saveError = error.localizedDescription
      }
    }

    func saveJSONPreview(defaultName: String) async {
      let fallback = defaultName.isEmpty ? "result" : defaultName
      let name = lastSuggestedName.isEmpty ? fallback : lastSuggestedName
      guard let jsonPreview, let data = jsonPreview.data(using: .utf8) else { return }
      saveError = nil
      guard
        let output = await Self.askSave(
          basename: name, type: .json, directory: defaultSaveDirectory())
      else {
        return
      }
      do {
        try data.write(to: output, options: .atomic)
        rememberSaveDirectory(output)
        resultSaved = true
        jobStatus = .succeeded(output.path(percentEncoded: false))
      } catch {
        saveError = error.localizedDescription
      }
    }

    func revealResult() {
      guard case .succeeded(let path) = jobStatus else { return }
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func pollLoop() async {
      while !Task.isCancelled {
        await refreshStatus()
        let delay: Duration = isStarting ? .milliseconds(400) : .seconds(2)
        try? await Task.sleep(for: delay)
      }
    }

    private func refreshStatus() async {
      if usesRemote {
        if hasUnappliedRemoteURL { return }
        await refreshRemote(connecting: false)
        return
      }
      do {
        try client.connect()
        let dto = try await client.status()
        apply(dto)
      } catch {
        if case .starting = status { return }
        if case .idle = status { return }
        applyError(error)
      }
    }

    private func refreshRemote(connecting: Bool) async {
      if isStarting && !connecting { return }
      let connectionID = remoteConnectionID
      guard let url = settings.apiURL else {
        if connecting {
          applyError(EngineError.invalidEngineURL(EngineSettings.urlHint))
        } else {
          status = .idle
        }
        return
      }
      let credentials = appliedRemoteCredentials
      do {
        if let credentialLoadError { throw EngineError.operationFailed(credentialLoadError) }
        try await http.checkHealth(baseURL: url, credentials: credentials)
        // /health may be public while /version and conversions require authentication.
        // Probe the version on connection/reconnection, not on every health poll.
        let probeVersion = connecting || remoteWasReachable != true
        var version = gotenbergVersion
        if probeVersion {
          do {
            version = try await http.version(baseURL: url, credentials: credentials)
          } catch let error as EngineError {
            if case .convertFailed(let code, _) = error, code == 401 || code == 403 { throw error }
            version = nil
          } catch {
            version = nil
          }
        }
        guard remoteConnectionID == connectionID, settings.apiURL == url,
          appliedRemoteCredentials == credentials, usesRemote
        else { return }
        gotenbergVersion = version
        status = .running(url.absoluteString)
        if remoteWasReachable != true {
          noteRemote("Connected to \(url.absoluteString)")
        }
        remoteWasReachable = true
        return
      } catch {
        guard remoteConnectionID == connectionID, settings.apiURL == url,
          appliedRemoteCredentials == credentials, usesRemote
        else { return }
        let message = "Could not connect to Gotenberg: \(EngineError.message(for: error))"
        status = .failed(message)
        gotenbergVersion = nil
        if remoteWasReachable != false || connecting { noteRemote(message) }
        remoteWasReachable = false
      }
    }

    func compatibilityIssue(action: ConvertAction, fields: [MultipartField]) -> String? {
      guard
        let issue = GotenbergCompatibility.issue(
          version: gotenbergVersion, path: action.path, fields: fields)
      else { return nil }
      return issue
        + (usesRemote
          ? " Update the custom server to use this feature."
          : " Use Refresh Image to update the built-in engine.")
    }

    func checkEngineUpdate() async {
      guard !checkingEngineUpdate else { return }
      checkingEngineUpdate = true
      engineUpdateError = nil
      defer { checkingEngineUpdate = false }
      do {
        latestGotenbergRelease = try await releaseChecker.latest()
      } catch {
        engineUpdateError = EngineError.message(for: error)
      }
    }

    var engineUpdateAvailable: Bool {
      guard let gotenbergVersion, let current = AppVersionModel(gotenbergVersion),
        let latestGotenbergRelease, let latest = AppVersionModel(latestGotenbergRelease.version)
      else { return false }
      return current < latest
    }

    private func noteRemote(_ message: String) {
      if logs.last?.message == message { return }
      EngineLogEntry.append(message, to: &logs)
    }

    func clearLogs() async {
      logs = []
      if usesRemote {
        return
      }
      do {
        try await client.clearLogs()
      } catch {
        EngineLogEntry.append(
          "Could not clear engine log: \(EngineError.message(for: error))", to: &logs)
      }
    }

    private func persistSettings() {
      do {
        try settings.save()
      } catch {
        applyError(error)
      }
    }

    private func apply(_ dto: EngineStatusDTO) {
      gotenbergVersion = dto.gotenbergVersion
      if logs != dto.logs {
        logs = dto.logs
      }
      if imageDigest != dto.imageDigest {
        imageDigest = dto.imageDigest
      }
      let next: Status =
        switch dto.phase {
        case "running":
          .running(dto.guestURL ?? "")
        case "starting":
          .starting(dto.phaseLabel)
        case "failed":
          .failed(dto.failedMessage ?? "Engine failed")
        default:
          .idle
        }
      if status != next {
        status = next
      }
    }

    private func applyError(_ error: Error) {
      status = .failed(EngineError.message(for: error))
    }

    static func stageFiles(
      jobID: String, action: ConvertAction, fields: [MultipartField],
      files: [(field: String, url: URL)]
    ) throws -> [FileRefDTO] {
      let root = Paths.jobDirectory(jobID)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      // Gotenberg alphanumeric-sorts the `files` field by original filename.
      // Prefix those jobs so picker order is merge order. Chromium, embeds,
      // and other name-sensitive routes need the literal original name.
      let preservePickerOrder =
        action.id == "pdf-merge" || fields.firstValue(for: "merge") == "true"
      let orderWidth = max(1, String(max(0, files.count - 1)).count)
      var usedNames: Set<String> = []
      var refs: [FileRefDTO] = []
      for (index, pair) in files.enumerated() {
        let accessed = pair.url.startAccessingSecurityScopedResource()
        defer {
          if accessed {
            pair.url.stopAccessingSecurityScopedResource()
          }
        }
        if FileSlot.isDroppedDirectory(pair.url) {
          throw EngineError.stagingFailed(
            "'\(pair.url.lastPathComponent)' is a folder. Choose a file.")
        }
        let original = pair.url.lastPathComponent
        let order = String(format: "%0\(orderWidth)d", index)
        // Marks are consumed in upload order and may reuse the same source file.
        // Give them unique names even on engines predating duplicate-name support.
        let isMark = pair.field == "stamp" || pair.field == "watermark"
        let filename =
          isMark
          ? "\(pair.field)-\(UUID().uuidString).\(pair.url.pathExtension)"
          : (preservePickerOrder ? "\(order)-\(original)" : original)
        if !usedNames.insert(filename).inserted {
          throw EngineError.stagingFailed(
            "Two files are named '\(filename)'. Gotenberg looks files up by name; rename one of them."
          )
        }
        let dest = root.appendingPathComponent("\(order)-\(original)")
        try FileManager.default.copyItem(at: pair.url, to: dest)
        refs.append(
          FileRefDTO(
            field: pair.field, path: dest.path(percentEncoded: false), filename: filename))
      }
      return refs
    }

    private func discardUnsavedResult() {
      guard !resultSaved, let unsavedJobDirectory else {
        self.unsavedJobDirectory = nil
        return
      }
      try? FileManager.default.removeItem(at: unsavedJobDirectory)
      self.unsavedJobDirectory = nil
    }

    private func discardUnsavedJobDirectoryKeepingResult() {
      guard let unsavedJobDirectory else { return }
      defer { self.unsavedJobDirectory = nil }
      if case .succeeded(let path) = jobStatus {
        let resultPath = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
        let root = unsavedJobDirectory.standardizedFileURL.path(percentEncoded: false)
        if resultPath == root || resultPath.hasPrefix(root + "/") {
          return
        }
      }
      try? FileManager.default.removeItem(at: unsavedJobDirectory)
    }

    private func rememberSaveDirectory(_ url: URL) {
      let directory = url.deletingLastPathComponent()
      lastSaveDirectory = directory
      suggestedSaveDirectory = directory
      UserDefaults.standard.set(
        directory.path(percentEncoded: false), forKey: Self.lastSaveDirectoryKey)
    }

    private func defaultSaveDirectory() -> URL? {
      if resultSaved, case .succeeded(let path) = jobStatus {
        return URL(fileURLWithPath: path).deletingLastPathComponent()
      }
      for candidate in [suggestedSaveDirectory, lastSaveDirectory] {
        if let candidate, Self.directoryExists(candidate) {
          return candidate
        }
      }
      return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private static func directoryExists(_ url: URL) -> Bool {
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(
        atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        && isDirectory.boolValue
    }

    private static func askSave(basename: String, type: UTType, directory: URL?) async -> URL? {
      let panel = NSSavePanel()
      panel.allowedContentTypes = [type]
      panel.nameFieldStringValue = basename
      panel.canCreateDirectories = true
      panel.isExtensionHidden = false
      if let directory, directoryExists(directory) {
        panel.directoryURL = directory
      }
      let window = NSApp.keyWindow ?? NSApp.mainWindow
      return await withCheckedContinuation { continuation in
        let finish: (NSApplication.ModalResponse) -> Void = { response in
          let url = response == .OK ? panel.url : nil
          continuation.resume(returning: url)
        }
        if let window {
          panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
          finish(panel.runModal())
        }
      }
    }

    private static func utType(for ext: String) -> UTType {
      switch ext {
      case "pdf": .pdf
      case "json": .json
      case "zip": .zip
      case "png": .png
      case "jpg", "jpeg": .jpeg
      case "webp": UTType(filenameExtension: "webp") ?? .png
      default: .data
      }
    }
  }

#endif
