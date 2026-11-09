#if os(macOS) && arch(arm64)

  import Foundation
  import UniformTypeIdentifiers

  enum ActionGroup: String, CaseIterable, Identifiable {
    case chromium = "Chromium"
    case libreOffice = "LibreOffice"
    case pdf = "PDF"

    var id: String { rawValue }
  }

  enum ActionOutput: Hashable {
    case pdf
    case image
    case json
    case zipOrPdf
    case zip
  }

  struct FormField: Identifiable, Hashable {
    enum Kind: Hashable {
      case text
      case secure
      case toggle
      case picker([String])
      case multiline
    }

    var id: String { key }
    let key: String
    let label: String
    let kind: Kind
    let defaultValue: String
    var section: String = "Options"
    var placeholder: String = ""
    var sendDefault: Bool = false
    var help: String = ""
    var showsCaption: Bool = false
  }

  struct FieldPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let values: [String: String]

    static let customID = "custom"
  }

  struct PresetGroup: Hashable {
    enum Match: Hashable {
      case exact
      case number
      case json
    }

    let id: String
    let match: Match
    let presets: [FieldPreset]

    func matching(_ current: [String: String]) -> String {
      for preset in presets where matches(preset, current) {
        return preset.id
      }
      return FieldPreset.customID
    }

    func apply(_ id: String, to values: inout [String: String]) {
      guard let preset = presets.first(where: { $0.id == id }) else { return }
      for (key, value) in preset.values {
        values[key] = value
      }
    }

    private func matches(_ preset: FieldPreset, _ current: [String: String]) -> Bool {
      preset.values.allSatisfy { key, expected in
        equal(current[key] ?? "", expected)
      }
    }

    private func equal(_ left: String, _ right: String) -> Bool {
      let a = left.trimmingCharacters(in: .whitespacesAndNewlines)
      let b = right.trimmingCharacters(in: .whitespacesAndNewlines)
      switch match {
      case .exact:
        return a == b
      case .number:
        if a.isEmpty && b.isEmpty { return true }
        guard let na = Double(a), let nb = Double(b) else { return a == b }
        return abs(na - nb) < 0.0001
      case .json:
        return Self.jsonEqual(a, b)
      }
    }

    private static func jsonEqual(_ left: String, _ right: String) -> Bool {
      if left == right { return true }
      guard let leftData = left.data(using: .utf8), let rightData = right.data(using: .utf8),
        let leftObject = try? JSONSerialization.jsonObject(with: leftData),
        let rightObject = try? JSONSerialization.jsonObject(with: rightData)
      else {
        return false
      }
      switch (leftObject, rightObject) {
      case (let lhs as NSArray, let rhs as NSArray):
        return lhs.isEqual(rhs)
      case (let lhs as NSDictionary, let rhs as NSDictionary):
        return lhs.isEqual(rhs)
      default:
        return false
      }
    }
  }

  enum FieldPresets {
    // https://gotenberg.dev/docs/convert-with-chromium/convert-html-to-pdf
    static let paperSize = PresetGroup(
      id: "paperSize",
      match: .number,
      presets: [
        FieldPreset(
          id: "letter", title: "Letter", values: ["paperWidth": "8.5", "paperHeight": "11"]),
        FieldPreset(
          id: "legal", title: "Legal", values: ["paperWidth": "8.5", "paperHeight": "14"]),
        FieldPreset(
          id: "tabloid", title: "Tabloid", values: ["paperWidth": "11", "paperHeight": "17"]),
        FieldPreset(
          id: "ledger", title: "Ledger", values: ["paperWidth": "17", "paperHeight": "11"]),
        FieldPreset(id: "a4", title: "A4", values: ["paperWidth": "8.27", "paperHeight": "11.7"]),
        FieldPreset(id: "a3", title: "A3", values: ["paperWidth": "11.7", "paperHeight": "16.54"]),
        FieldPreset(id: "a5", title: "A5", values: ["paperWidth": "5.83", "paperHeight": "8.27"]),
        FieldPreset(id: "a6", title: "A6", values: ["paperWidth": "4.13", "paperHeight": "5.83"]),
        FieldPreset(id: "a2", title: "A2", values: ["paperWidth": "16.54", "paperHeight": "23.4"]),
        FieldPreset(id: "a1", title: "A1", values: ["paperWidth": "23.4", "paperHeight": "33.1"]),
        FieldPreset(id: "a0", title: "A0", values: ["paperWidth": "33.1", "paperHeight": "46.8"]),
      ])

    static let margins = PresetGroup(
      id: "margins",
      match: .number,
      presets: [
        FieldPreset(id: "none", title: "None", values: Self.marginValues("0")),
        FieldPreset(id: "narrow", title: "Narrow", values: Self.marginValues("0.25")),
        FieldPreset(id: "default", title: "Default", values: Self.marginValues("0.39")),
        FieldPreset(id: "moderate", title: "Moderate", values: Self.marginValues("0.75")),
        FieldPreset(id: "wide", title: "Wide", values: Self.marginValues("1")),
      ])

    static let scale = PresetGroup(
      id: "scale",
      match: .number,
      presets: [
        FieldPreset(id: "50", title: "50%", values: ["scale": "0.5"]),
        FieldPreset(id: "75", title: "75%", values: ["scale": "0.75"]),
        FieldPreset(id: "100", title: "100%", values: ["scale": "1.0"]),
        FieldPreset(id: "125", title: "125%", values: ["scale": "1.25"]),
        FieldPreset(id: "150", title: "150%", values: ["scale": "1.5"]),
      ])

    static let captureSize = PresetGroup(
      id: "captureSize",
      match: .number,
      presets: [
        FieldPreset(id: "800x600", title: "800 × 600", values: ["width": "800", "height": "600"]),
        FieldPreset(
          id: "1280x720", title: "1280 × 720", values: ["width": "1280", "height": "720"]),
        FieldPreset(
          id: "1920x1080", title: "1920 × 1080", values: ["width": "1920", "height": "1080"]),
        FieldPreset(id: "iphone", title: "iPhone", values: ["width": "390", "height": "844"]),
        FieldPreset(id: "ipad", title: "iPad", values: ["width": "1024", "height": "1366"]),
      ])

    static let deviceScale = PresetGroup(
      id: "deviceScale",
      match: .number,
      presets: [
        FieldPreset(id: "1x", title: "1×", values: ["deviceScaleFactor": "1.0"]),
        FieldPreset(id: "2x", title: "2×", values: ["deviceScaleFactor": "2.0"]),
        FieldPreset(id: "3x", title: "3×", values: ["deviceScaleFactor": "3.0"]),
      ])

    static let waitDelay = PresetGroup(
      id: "waitDelay",
      match: .exact,
      presets: [
        FieldPreset(id: "none", title: "None", values: ["waitDelay": ""]),
        FieldPreset(id: "500ms", title: "500 ms", values: ["waitDelay": "500ms"]),
        FieldPreset(id: "1s", title: "1 s", values: ["waitDelay": "1s"]),
        FieldPreset(id: "2s", title: "2 s", values: ["waitDelay": "2s"]),
        FieldPreset(id: "5s", title: "5 s", values: ["waitDelay": "5s"]),
      ])

    static let userAgent = PresetGroup(
      id: "userAgent",
      match: .exact,
      presets: [
        FieldPreset(id: "default", title: "Default", values: ["userAgent": ""]),
        FieldPreset(
          id: "desktop", title: "Desktop Chrome",
          values: [
            "userAgent":
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
          ]),
        FieldPreset(
          id: "iphone", title: "iPhone Safari",
          values: [
            "userAgent":
              "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
          ]),
      ])

    static let colorScheme = PresetGroup(
      id: "colorScheme",
      match: .json,
      presets: [
        FieldPreset(id: "default", title: "Default", values: ["emulatedMediaFeatures": ""]),
        FieldPreset(
          id: "light", title: "Light",
          values: [
            "emulatedMediaFeatures": #"[{"name":"prefers-color-scheme","value":"light"}]"#
          ]),
        FieldPreset(
          id: "dark", title: "Dark",
          values: [
            "emulatedMediaFeatures": #"[{"name":"prefers-color-scheme","value":"dark"}]"#
          ]),
      ])

    static func quality(key: String, emptyTitle: String? = nil) -> PresetGroup {
      var presets: [FieldPreset] = []
      if let emptyTitle {
        presets.append(FieldPreset(id: "none", title: emptyTitle, values: [key: ""]))
      }
      for value in ["60", "75", "80", "90", "100"] {
        presets.append(FieldPreset(id: value, title: value, values: [key: value]))
      }
      return PresetGroup(id: "quality.\(key)", match: .number, presets: presets)
    }

    private static func marginValues(_ inches: String) -> [String: String] {
      [
        "marginTop": inches,
        "marginBottom": inches,
        "marginLeft": inches,
        "marginRight": inches,
      ]
    }
  }

  struct FileSlot: Hashable {
    let field: String
    let label: String
    let types: [UTType]
    let allowsMultiple: Bool
    let help: String
    var minimumCount: Int = 1
    var required: Bool = true
    // Empty means any file. Only Embed attachments use that.
    var extensions: Set<String> = []
    // Each set must appear at least once among selected files.
    var mustInclude: [Set<String>] = []
    // Gotenberg looks these up by exact filename.
    var requiredNames: [String] = []

    func accepts(_ url: URL) -> Bool {
      guard !Self.isDroppedDirectory(url) else { return false }
      guard !extensions.isEmpty else { return true }
      return extensions.contains(url.pathExtension.lowercased())
    }

    // Folders are not sources. iWork packages (.pages, .numbers, .key) are
    // directories on disk but documents in the picker, so they stay allowed.
    static func isDroppedDirectory(_ url: URL) -> Bool {
      let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
      return values?.isDirectory == true && values?.isPackage != true
    }

    func accepted(from urls: [URL]) -> [URL] {
      urls.filter(accepts)
    }

    // UTTypes used by the Open dialog. Drops parent types such as
    // public.plain-text, which would also enable .md and other text files.
    var pickerTypes: [UTType] {
      if extensions.isEmpty {
        return types.isEmpty ? ConvertUTType.any : types
      }
      let filtered = types.filter { !ConvertUTType.isBroad($0) }
      return filtered.isEmpty ? [.item] : filtered
    }

    func refined(types: [UTType], extensions: Set<String>, help: String) -> FileSlot {
      FileSlot(
        field: field,
        label: label,
        types: types,
        allowsMultiple: allowsMultiple,
        help: help,
        minimumCount: minimumCount,
        required: required,
        extensions: extensions,
        mustInclude: mustInclude,
        requiredNames: requiredNames)
    }

    func rejection(for urls: [URL]) -> String? {
      if let folder = urls.first(where: { Self.isDroppedDirectory($0) }) {
        return "'\(folder.lastPathComponent)' is a folder. Choose a file."
      }
      if let bad = urls.first(where: { !accepts($0) }) {
        return Self.sourceMismatch(
          filename: bad.lastPathComponent,
          ext: bad.pathExtension.lowercased(),
          allowed: extensions)
      }
      for group in mustInclude {
        let present = urls.contains { group.contains($0.pathExtension.lowercased()) }
        if !present {
          return "Add a \(group.sorted().joined(separator: " or ")) file."
        }
      }
      for name in requiredNames {
        let present = urls.contains { $0.lastPathComponent == name }
        if !present {
          return "Include \(name). Gotenberg looks up this file by name."
        }
      }
      return nil
    }

    private static func sourceMismatch(filename: String, ext: String, allowed: Set<String>)
      -> String
    {
      if ext == "markdown" {
        return "'\(filename)' uses .markdown. This action needs a .md file."
      }
      if ConvertUTType.pdfExtensions.contains(ext), !allowed.contains("pdf") {
        return "'\(filename)' is a PDF. Use Merge or another PDF action."
      }
      if ConvertUTType.officeExtensions.contains(ext),
        allowed.isDisjoint(with: ConvertUTType.officeExtensions)
      {
        return "'\(filename)' is an office document. Use Office to PDF."
      }
      if ConvertUTType.htmlExtensions.contains(ext),
        allowed.isDisjoint(with: ConvertUTType.htmlExtensions)
      {
        return "'\(filename)' is HTML. Use HTML to PDF or HTML screenshot."
      }
      if ConvertUTType.markdownExtensions.contains(ext),
        allowed.isDisjoint(with: ConvertUTType.markdownExtensions)
      {
        return "'\(filename)' is Markdown. Use Markdown to PDF or Markdown screenshot."
      }
      if ConvertUTType.xmlExtensions.contains(ext), !allowed.contains("xml") {
        return "'\(filename)' is XML. Use Factur-X to inject invoice XML into a PDF."
      }
      if ConvertUTType.imageExtensions.contains(ext) {
        if allowed == ConvertUTType.pdfExtensions {
          return "'\(filename)' is an image. This action takes a PDF."
        }
        if allowed == ConvertUTType.officeExtensions {
          return "'\(filename)' is an image. Office to PDF takes documents, not images."
        }
      }
      if ConvertUTType.pdfExtensions.contains(ext), allowed == ConvertUTType.imageExtensions {
        return "'\(filename)' is a PDF. Switch Source to pdf, or choose a PNG, JPEG, or WebP."
      }
      if allowed.isEmpty {
        return "'\(filename)' is not a valid source here."
      }
      return
        "'\(filename)' is not a valid source here. Allowed: \(allowed.sorted().joined(separator: ", "))."
    }
  }

  struct ConvertAction: Identifiable, Hashable {
    enum Composer: Hashable {
      case fields
      case stamps
      case finishing
    }

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let group: ActionGroup
    let path: String
    let urlField: Bool
    let files: FileSlot?
    let extraFiles: [FileSlot]
    let fields: [FormField]
    let output: ActionOutput
    let defaultFilename: String
    var composer: Composer = .fields

    var runTitle: String {
      switch output {
      case .json:
        "Read"
      case .image:
        "Capture"
      case .pdf:
        group == .pdf ? title : "Convert to PDF"
      case .zipOrPdf, .zip:
        title
      }
    }

    var outputExtension: String? {
      switch output {
      case .pdf, .zipOrPdf: "pdf"
      case .json: "json"
      case .image: nil
      case .zip: "zip"
      }
    }

    static let all: [ConvertAction] = chromium + libreOffice + pdfActions

    static func grouped() -> [(ActionGroup, [ConvertAction])] {
      ActionGroup.allCases.map { group in
        (group, all.filter { $0.group == group })
      }
    }
  }

  enum ConvertUTType {
    static let pdfExtensions: Set<String> = ["pdf"]
    static let xmlExtensions: Set<String> = ["xml"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
    static let htmlExtensions: Set<String> = ["html", "htm"]
    // Gotenberg markdown routes require .md, not .markdown.
    static let markdownExtensions: Set<String> = ["md"]
    static let webAssetExtensions: Set<String> = [
      "css", "js", "mjs", "json", "svg", "png", "jpg", "jpeg", "gif", "webp", "ico",
      "woff", "woff2", "ttf", "otf", "eot",
    ]
    static let htmlSources = htmlExtensions.union(webAssetExtensions)
    static let markdownSources = htmlExtensions.union(markdownExtensions).union(webAssetExtensions)

    // Job list for Office to PDF. Not LibreOffice.Extensions(), which also
    // accepts PDF, HTML, and images that belong to other actions.
    static let officeExtensions: Set<String> = [
      "doc", "docm", "docx", "dot", "dotm", "dotx", "odt", "ott", "fodt", "rtf",
      "pages", "abw", "hwp", "lwp", "wpd", "wps",
      "xls", "xlsb", "xlsm", "xlsx", "xlt", "xltm", "xltx", "xlw", "ods", "ots", "fods",
      "csv", "slk", "dif", "dbf", "numbers",
      "ppt", "pptm", "pptx", "pot", "potm", "potx", "pps", "ppsm", "ppsx",
      "odp", "otp", "fodp", "key",
      "odg", "otg", "fodg", "odm", "pub", "vsd", "vsdm", "vsdx",
    ]

    static let pdf = types(pdfExtensions)
    static let html = types(htmlExtensions)
    static let markdown = types(markdownSources)
    static let office = types(officeExtensions)
    static let xml = types(xmlExtensions)
    static let images = types(imageExtensions)
    static let htmlAndAssets = types(htmlSources)
    static let any = [UTType.data]

    static func types(_ extensions: Set<String>) -> [UTType] {
      extensions.compactMap { ext in
        guard let type = UTType(filenameExtension: ext), !isBroad(type) else {
          return nil
        }
        return type
      }
    }

    static func isBroad(_ type: UTType) -> Bool {
      let parents: [UTType] = [
        .item, .content, .data, .text, .plainText, .utf8PlainText, .utf16PlainText,
        .sourceCode,
      ]
      return parents.contains { $0 == type }
    }
  }

  enum FieldHelp {
    struct Entry {
      var text: String
      var caption: Bool = false
    }

    static func text(_ key: String) -> String {
      all[key]?.text ?? ""
    }

    static func showsCaption(_ key: String) -> Bool {
      all[key]?.caption ?? false
    }

    private static let all: [String: Entry] = [
      "landscape": Entry(text: "Landscape page orientation."),
      "printBackground": Entry(text: "Print CSS backgrounds and images."),
      "preferCssPageSize": Entry(
        text: "Use the CSS @page size instead of paper width and height.", caption: true),
      "singlePage": Entry(
        text: "Chromium: fit the whole document on one page. LibreOffice: one page per sheet.",
        caption: true),
      "scale": Entry(text: "Page render scale. 100% is Chromium's default."),
      "paperWidth": Entry(
        text:
          "Standard paper size, or custom width and height in inches. Ignored when Prefer CSS page size is on."
      ),
      "paperHeight": Entry(text: "Paper height in inches."),
      "marginTop": Entry(text: "Page margins in inches. Ignored when Prefer CSS page size is on."),
      "marginBottom": Entry(text: "Bottom margin in inches."),
      "marginLeft": Entry(text: "Left margin in inches."),
      "marginRight": Entry(text: "Right margin in inches."),
      "nativePages": Entry(
        text: "Pages to print, e.g. 1-5, 8, 11-13. Empty means every page.", caption: true),
      "nativeBookmarks": Entry(
        text: "Embed a PDF outline from headings.", caption: true),
      "nativeTaggedPdf": Entry(
        text:
          "Build an accessible tagged PDF in Chromium. Prefer this for HTML and URL conversions.",
        caption: true),
      "paperSize": Entry(
        text: "Named paper size. Custom width and height still apply when set.", caption: true),
      "omitBackground": Entry(
        text: "Hide the default white background so the PDF or image can be transparent."),
      "waitDelay": Entry(
        text:
          "Fixed pause before print, e.g. 5s or 500ms. Prefer a selector or expression when you can. Custom uses Gotenberg's duration string.",
        caption: true),
      "waitForSelector": Entry(
        text: "CSS selector. Print starts when that element is visible.", caption: true),
      "waitForExpression": Entry(
        text: "JavaScript that must return true before print, e.g. window.status === 'ready'.",
        caption: true),
      "waitForWindowStatus": Entry(
        text: "Wait until window.status equals this string.", caption: true),
      "skipNetworkIdleEvent": Entry(
        text:
          "On by default. Does not wait for Chromium networkIdle, which is faster but can cut off late-loading pages.",
        caption: true),
      "skipNetworkAlmostIdleEvent": Entry(
        text: "On by default. Does not wait for Chromium networkAlmostIdle.", caption: true),
      "failOnHttpStatusCodes": Entry(
        text: "JSON array of main-document status codes that fail the request. Default [499,599].",
        caption: true),
      "failOnResourceHttpStatusCodes": Entry(
        text: "JSON array of subresource status codes that fail the request, e.g. [404,500].",
        caption: true),
      "ignoreResourceHttpStatusDomains": Entry(
        text:
          "JSON array of hostnames excluded from Fail on resource HTTP status codes. Subdomains match.",
        caption: true),
      "failOnResourceLoadingFailed": Entry(text: "Fail if Chromium cannot load any page resource."),
      "failOnConsoleExceptions": Entry(text: "Fail if the page logs a JavaScript exception."),
      "userAgent": Entry(
        text:
          "Override Chromium's User-Agent. Default keeps the engine browser string. Custom is the raw header value."
      ),
      "emulatedMediaType": Entry(
        text: "CSS media type. print uses @media print. screen uses @media screen.", caption: true),
      "cookies": Entry(
        text: "JSON array of cookies. Each object needs name, value, and domain."),
      "extraHttpHeaders": Entry(
        text:
          "JSON object of header names to values. A value may include scope= to match request URLs.",
        caption: true),
      "emulatedMediaFeatures": Entry(
        text:
          "Light and Dark set prefers-color-scheme. Custom is a JSON array of CSS media feature objects.",
        caption: true),
      "nativePdfa": Entry(
        text: "LibreOffice writes PDF/A during export. Empty leaves standard PDF."),
      "angle": Entry(text: "Clockwise rotation in degrees."),
      "nativePdfua": Entry(
        text: "LibreOffice writes PDF/UA-1 during export. Empty leaves standard PDF.",
        caption: true),
      "nativeQuality": Entry(text: "JPEG quality from 1 to 100 when exporting images."),
      "nativeLosslessImageCompression": Entry(
        text: "Export images as lossless PNG instead of JPEG."),
      "nativeReduceImageResolution": Entry(text: "Downsample images to Max image DPI."),
      "nativeMaxImageResolution": Entry(text: "Target DPI when Reduce image resolution is on."),
      "splitMode": Entry(
        text: "intervals sends every N pages. pages sends a range list.", caption: true),
      "every": Entry(text: "Split every N pages when Mode is intervals.", caption: true),
      "ranges": Entry(
        text: "Comma list or JSON array of page ranges when Mode is pages, e.g. 1-3,5.",
        caption: true),
      "userPassword": Entry(
        text: "Password required to open the PDF. Leave empty for owner-only encryption."),
      "ownerPassword": Entry(
        text: "Password for changing permissions. One of the two passwords is required to encrypt."),
      "print": Entry(text: "Allow printing when the user password is used."),
      "printHighQuality": Entry(text: "Allow high-quality printing."),
      "modifyContent": Entry(text: "Allow changing page content."),
      "extractText": Entry(text: "Allow copying text and images."),
      "modifyAnnotations": Entry(text: "Allow comments and markup."),
      "fillForms": Entry(text: "Allow filling interactive form fields."),
      "assemble": Entry(
        text: "Allow inserting, rotating, and deleting pages.", caption: true),
      "password": Entry(text: "Password for an encrypted office document."),
      "updateIndexes": Entry(
        text: "Refresh indexes before convert. Can drop some links in the PDF.", caption: true),
      "exportBookmarks": Entry(text: "Write the office outline as PDF bookmarks."),
      "exportBookmarksToPdfDestination": Entry(
        text: "Export bookmarks as named PDF destinations.", caption: true),
      "exportFormFields": Entry(
        text: "Export form fields as widgets. Off writes only their printed appearance."),
      "allowDuplicateFieldNames": Entry(
        text: "Allow more than one exported form field to share a name."),
      "exportPlaceholders": Entry(
        text: "Export placeholder marks only. They are not fillable fields.", caption: true),
      "exportNotes": Entry(text: "Include document notes in the PDF."),
      "exportNotesPages": Entry(text: "Impress only. Export notes pages."),
      "exportOnlyNotesPages": Entry(
        text: "Impress only. Export notes pages and skip slides. Needs Export notes pages."),
      "exportNotesInMargin": Entry(text: "Export notes that sit in the page margin."),
      "convertOooTargetToPdfTarget": Entry(
        text: "Rewrite links to .odt, .ods, .odp, and similar files so they point at .pdf.",
        caption: true),
      "exportLinksRelativeFsys": Entry(
        text: "Export file:// links relative to the source document.", caption: true),
      "exportHiddenSlides": Entry(text: "Impress only. Include slides hidden from the slideshow."),
      "skipEmptyPages": Entry(text: "Writer only. Drop automatically inserted empty pages."),
      "addOriginalDocumentAsStream": Entry(
        text: "Embed the original office file inside the PDF for archiving.", caption: true),
      "initialView": Entry(
        text: "What the PDF viewer shows on open: default, outline, or thumbnails."),
      "initialPage": Entry(text: "Page shown when the PDF opens."),
      "magnification": Entry(
        text: "Open zoom. zoom applies the Zoom percent field.", caption: true),
      "zoom": Entry(text: "Open zoom percent. Used when Magnification is Use zoom."),
      "pageLayout": Entry(text: "Page layout when the PDF opens."),
      "openBookmarkLevels": Entry(
        text: "How many outline levels are expanded. All opens every level."),
      "resizeWindowToInitialPage": Entry(text: "Resize the viewer window to the first page."),
      "centerWindow": Entry(text: "Center the viewer window on screen."),
      "openInFullScreenMode": Entry(text: "Open the viewer full screen."),
      "displayPDFDocumentTitle": Entry(text: "Show the document title in the viewer title bar."),
      "hideViewerMenubar": Entry(text: "Hide the PDF viewer menu bar."),
      "hideViewerToolbar": Entry(text: "Hide the PDF viewer toolbar."),
      "hideViewerWindowControls": Entry(text: "Hide the PDF viewer window controls."),
      "useTransitionEffects": Entry(text: "Impress only. Export slide transitions."),
      "nativeWatermarkText": Entry(text: "LibreOffice watermark drawn on every page."),
      "nativeTiledWatermarkText": Entry(text: "LibreOffice tiled watermark text."),
      "nativeWatermarkColor": Entry(
        text: "Watermark color as #rrggbb hex.", caption: true),
      "nativeWatermarkFontSize": Entry(text: "Watermark font size in points."),
      "nativeWatermarkFont": Entry(text: "Watermark font name."),
      "nativeWatermarkRotation": Entry(
        text: "Watermark rotation in degrees.", caption: true),
      "title": Entry(text: "Document title."),
      "author": Entry(text: "Document author."),
      "subject": Entry(text: "Document subject."),
      "keywords": Entry(text: "Document keywords."),
      "creator": Entry(text: "Creating application."),
      "producer": Entry(text: "PDF producer."),
      "creationDate": Entry(text: "Creation date string."),
      "modDate": Entry(text: "Modification date string."),
      "bookmarks": Entry(
        text: "JSON array with title, pageNumber, and optional children.", caption: true),
      "pages": Entry(
        text: "Page list, e.g. 1-3,5. Empty often means every page.", caption: true),
      "profile": Entry(text: "Remediation or validation profile."),
      "language": Entry(text: "Document language for remediation, e.g. en."),
      "aggressive": Entry(text: "Aggressive remediation fixes."),
      "figureAltText": Entry(text: "Default alt text for figures during remediation."),
      "level": Entry(text: "Factur-X conformance level."),
      "documentType": Entry(text: "Factur-X business document type."),
      "objectStreams": Entry(text: "Use object streams when optimizing."),
      "dedup": Entry(text: "Remove duplicate objects when optimizing."),
      "recompressImages": Entry(text: "Recompress images when optimizing."),
      "subsetFonts": Entry(text: "Subset embedded fonts when optimizing."),
      "algorithm": Entry(text: "Encryption algorithm. aes256 is recommended."),
      "space": Entry(text: "Target color space: Gray, RGB, or CMYK."),
      "regions": Entry(
        text: "JSON array of redaction regions with page, x, y, width, height.", caption: true),
      "fields": Entry(text: "JSON object of AcroForm field names to values."),
      "placements": Entry(text: "JSON array of compose placements.", caption: true),
      "dpi": Entry(text: "Render resolution in dots per inch."),
      "format": Entry(text: "Render or screenshot image format."),
      "invisible": Entry(text: "Include invisible text when extracting."),
      "artifacts": Entry(text: "Include artifacts when extracting text."),
      "annotations": Entry(text: "Include annotations when extracting text."),
      "name": Entry(text: "Attachment name to detach or extract."),
      "file": Entry(text: "Attachment filename on disk (for attach via pipe)."),
      "at": Entry(
        text: "Insert after this page. 0 inserts before the first page.", caption: true),
      "sourcePages": Entry(
        text: "Pages of the source PDF to insert, e.g. all or 1-3.", caption: true),
      "url": Entry(text: "Timestamp authority URL."),
      "reason": Entry(text: "Reason shown in the digital signature."),
      "location": Entry(text: "Location shown in the digital signature."),
      "certificatePassword": Entry(text: "Password that opens a PKCS#12 certificate."),
      "pades": Entry(text: "Create a PAdES signature for eIDAS."),
      "contactInfo": Entry(text: "Contact shown in the signature panel."),
      "timestampUrl": Entry(text: "RFC 3161 timestamp authority for the signature."),
      "certificate": Entry(text: "PKCS#12 or certificate file for signing."),
      "width": Entry(text: "Capture width and height in CSS pixels."),
      "height": Entry(text: "Capture height in CSS pixels."),
      "deviceScaleFactor": Entry(text: "Device pixel ratio. 2× is a Retina-density capture."),
      "clip": Entry(text: "Clip the screenshot to Width and Height instead of the full page."),
      "selector": Entry(text: "Capture only the first element that matches this CSS selector."),
      "optimizeForSpeed": Entry(text: "Faster encode with a larger file."),
    ]
  }

  func text(
    _ key: String, _ label: String, default defaultValue: String = "", section: String = "Options",
    placeholder: String = "", sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .text, defaultValue: defaultValue, section: section,
      placeholder: placeholder, sendDefault: sendDefault, help: FieldHelp.text(key),
      showsCaption: FieldHelp.showsCaption(key))
  }

  func secure(_ key: String, _ label: String, section: String = "Options") -> FormField {
    FormField(
      key: key, label: label, kind: .secure, defaultValue: "", section: section,
      help: FieldHelp.text(key), showsCaption: FieldHelp.showsCaption(key))
  }

  func toggle(
    _ key: String, _ label: String, default defaultValue: Bool = false, section: String = "Options",
    sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .toggle, defaultValue: defaultValue ? "true" : "false",
      section: section, sendDefault: sendDefault, help: FieldHelp.text(key),
      showsCaption: FieldHelp.showsCaption(key))
  }

  func picker(
    _ key: String, _ label: String, _ options: [String], default defaultValue: String,
    section: String = "Options", sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .picker(options), defaultValue: defaultValue, section: section,
      sendDefault: sendDefault, help: FieldHelp.text(key), showsCaption: FieldHelp.showsCaption(key)
    )
  }

  func multiline(
    _ key: String, _ label: String, default defaultValue: String = "", section: String = "Options",
    placeholder: String = "", sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .multiline, defaultValue: defaultValue, section: section,
      placeholder: placeholder, sendDefault: sendDefault, help: FieldHelp.text(key),
      showsCaption: FieldHelp.showsCaption(key))
  }

  /// LibreOffice `nativePdfa` values (export-time only).
  let pdfaOptions = [
    "", "PDF/A-1b", "PDF/A-2b", "PDF/A-3b", "PDF/A-4",
  ]

  /// litho `remediate` / `validate` profiles.
  let remediateProfiles = [
    "", "PDF/A-1a", "PDF/A-1b", "PDF/A-2a", "PDF/A-2b", "PDF/A-2u", "PDF/A-3a", "PDF/A-3b",
    "PDF/A-3u", "PDF/A-4", "PDF/A-4e", "PDF/A-4f", "PDF/UA-1", "PDF/UA-2", "Factur-X",
  ]

  let paperSizeOptions = [
    "", "Letter", "Legal", "Tabloid", "Ledger", "A4", "A3", "A5", "A6", "A2", "A1", "A0",
  ]

  let libreOfficeInitialView = ["default", "outline", "thumbnails"]
  let libreOfficeMagnification = [
    "default", "fitWindow", "fitWidth", "fitVisible", "zoom",
  ]
  let libreOfficePageLayout = [
    "default", "singlePage", "oneColumn", "twoColumnRight",
  ]

  func pdfOptimizeRouteFields() -> [FormField] {
    [
      toggle("objectStreams", "Object streams", default: true, sendDefault: true),
      toggle("dedup", "Deduplicate", default: true, sendDefault: true),
      toggle("recompressImages", "Recompress images", default: true, sendDefault: true),
      toggle("subsetFonts", "Subset fonts", default: true, sendDefault: true),
    ]
  }

  func pdfEncryptFields(section: String = "Encryption") -> [FormField] {
    [
      secure("userPassword", "User password", section: section),
      secure("ownerPassword", "Owner password", section: section),
      picker("algorithm", "Algorithm", ["aes128", "aes256"], default: "aes256", section: section),
      toggle("print", "Allow printing", default: true, section: section, sendDefault: true),
      toggle(
        "printHighQuality", "Allow print high quality", default: true, section: section,
        sendDefault: true),
      toggle("modifyContent", "Allow modify content", default: true, section: section),
      toggle("extractText", "Allow extract text", default: true, section: section),
      toggle("modifyAnnotations", "Allow modify annotations", default: true, section: section),
      toggle("fillForms", "Allow fill forms", default: true, section: section),
      toggle("assemble", "Allow assemble", default: true, section: section),
    ]
  }

  func pdfMetadataWriteFields() -> [FormField] {
    [
      text("title", "Title", section: "Metadata"),
      text("author", "Author", section: "Metadata"),
      text("subject", "Subject", section: "Metadata"),
      text("keywords", "Keywords", section: "Metadata"),
      text("creator", "Creator", section: "Metadata"),
      text("producer", "Producer", section: "Metadata"),
      text("creationDate", "Creation date", section: "Metadata"),
      text("modDate", "Modification date", section: "Metadata"),
    ]
  }

  func remediateFields(includeProfile: Bool = true) -> [FormField] {
    var fields: [FormField] = []
    if includeProfile {
      fields.append(
        picker(
          "profile", "Profile", remediateProfiles.filter { !$0.isEmpty }, default: "PDF/A-2b",
          section: "Remediate", sendDefault: true))
    }
    fields += [
      text("language", "Language", default: "en", section: "Remediate"),
      toggle("aggressive", "Aggressive", section: "Remediate"),
      text("figureAltText", "Figure alt text", section: "Remediate"),
      picker(
        "level", "Factur-X level",
        ["MINIMUM", "BASIC WL", "BASIC", "EN 16931", "EXTENDED", "XRECHNUNG"],
        default: "EN 16931", section: "Factur-X", sendDefault: true),
      picker(
        "documentType", "Document type",
        ["INVOICE", "ORDER", "ORDER_RESPONSE", "ORDER_CHANGE"],
        default: "INVOICE", section: "Factur-X", sendDefault: true),
    ]
    return fields
  }

  // FormDataChromiumOptions in pkg/modules/chromium/routes.go.
  func chromiumWaitFields() -> [FormField] {
    [
      text("waitDelay", "Wait delay", section: "Wait", placeholder: "0s"),
      text("waitForSelector", "Wait for selector", section: "Wait"),
      text("waitForExpression", "Wait for expression", section: "Wait"),
      text("waitForWindowStatus", "Wait for window status", section: "Wait"),
      toggle("skipNetworkIdleEvent", "Skip network idle", default: true, section: "Wait"),
      toggle(
        "skipNetworkAlmostIdleEvent", "Skip network almost idle", default: true, section: "Wait"),
      text(
        "failOnHttpStatusCodes", "Fail on HTTP status codes", section: "Wait",
        placeholder: "[499,599]"),
      text(
        "failOnResourceHttpStatusCodes", "Fail on resource HTTP status codes", section: "Wait",
        placeholder: "[]"),
      text(
        "ignoreResourceHttpStatusDomains", "Ignore resource status domains", section: "Wait",
        placeholder: "[]"),
      toggle("failOnResourceLoadingFailed", "Fail on resource loading failed", section: "Wait"),
      toggle("failOnConsoleExceptions", "Fail on console exceptions", section: "Wait"),
    ]
  }

  func chromiumRequestFields(mediaTypeDefault: String = "") -> [FormField] {
    [
      text("userAgent", "User agent", section: "Request"),
      picker(
        "emulatedMediaType", "Media type", ["", "screen", "print"], default: mediaTypeDefault,
        section: "Request"),
      multiline(
        "cookies", "Cookies JSON", section: "Request",
        placeholder: #"[{"name":"session","value":"1","domain":"example.com"}]"#),
      multiline(
        "extraHttpHeaders", "Extra headers JSON", section: "Request",
        placeholder: #"{"X-Custom-Header":"value"}"#),
      multiline(
        "emulatedMediaFeatures", "Color scheme", section: "Request",
        placeholder: #"[{"name":"prefers-color-scheme","value":"dark"}]"#),
    ]
  }

  func pdfFiles(_ help: String, multiple: Bool = false, minimumCount: Int = 1) -> FileSlot {
    FileSlot(
      field: "files",
      label: multiple ? "PDF files" : "PDF file",
      types: ConvertUTType.pdf,
      allowsMultiple: multiple,
      help: help,
      minimumCount: minimumCount,
      extensions: ConvertUTType.pdfExtensions
    )
  }

  extension ConvertAction {
    fileprivate static let chromium: [ConvertAction] = [
      ConvertAction(
        id: "chromium-url-pdf",
        title: "URL to PDF",
        subtitle: "Render a web page with Chromium",
        icon: "globe",
        group: .chromium,
        path: "/forms/chromium/convert/url",
        urlField: true,
        files: nil,
        extraFiles: [],
        fields: chromiumPDFFields,
        output: .pdf,
        defaultFilename: "page",
        composer: .finishing
      ),
      ConvertAction(
        id: "chromium-html-pdf",
        title: "HTML to PDF",
        subtitle: "index.html plus optional assets",
        icon: "chevron.left.forwardslash.chevron.right",
        group: .chromium,
        path: "/forms/chromium/convert/html",
        urlField: false,
        files: FileSlot(
          field: "files", label: "HTML and assets", types: ConvertUTType.htmlAndAssets,
          allowsMultiple: true,
          help:
            "Must include index.html. CSS, images, and fonts are optional page assets. Optional header.html and footer.html set the print header and footer. Not office documents or PDFs.",
          extensions: ConvertUTType.htmlSources,
          mustInclude: [ConvertUTType.htmlExtensions],
          requiredNames: ["index.html"]),
        extraFiles: [],
        fields: chromiumPDFFields,
        output: .pdf,
        defaultFilename: "document",
        composer: .finishing
      ),
      ConvertAction(
        id: "chromium-markdown-pdf",
        title: "Markdown to PDF",
        subtitle: "index.html wrapper plus .md files",
        icon: "text.alignleft",
        group: .chromium,
        path: "/forms/chromium/convert/markdown",
        urlField: false,
        files: FileSlot(
          field: "files", label: "HTML wrapper and Markdown",
          types: ConvertUTType.markdown, allowsMultiple: true,
          help:
            "Must include index.html and at least one .md file. Optional header.html and footer.html set the print header and footer. Not office documents or PDFs.",
          extensions: ConvertUTType.markdownSources,
          mustInclude: [ConvertUTType.htmlExtensions, ConvertUTType.markdownExtensions],
          requiredNames: ["index.html"]),
        extraFiles: [],
        fields: chromiumPDFFields,
        output: .pdf,
        defaultFilename: "markdown",
        composer: .finishing
      ),
      ConvertAction(
        id: "chromium-url-screenshot",
        title: "URL screenshot",
        subtitle: "Capture a web page",
        icon: "camera",
        group: .chromium,
        path: "/forms/chromium/screenshot/url",
        urlField: true,
        files: nil,
        extraFiles: [],
        fields: chromiumScreenshotFields,
        output: .image,
        defaultFilename: "screenshot"
      ),
      ConvertAction(
        id: "chromium-html-screenshot",
        title: "HTML screenshot",
        subtitle: "Capture local HTML",
        icon: "camera.viewfinder",
        group: .chromium,
        path: "/forms/chromium/screenshot/html",
        urlField: false,
        files: FileSlot(
          field: "files", label: "HTML and assets", types: ConvertUTType.htmlAndAssets,
          allowsMultiple: true,
          help:
            "Must include index.html. CSS, images, and fonts are optional page assets. Not office documents or PDFs.",
          extensions: ConvertUTType.htmlSources,
          mustInclude: [ConvertUTType.htmlExtensions],
          requiredNames: ["index.html"]),
        extraFiles: [],
        fields: chromiumScreenshotFields,
        output: .image,
        defaultFilename: "screenshot"
      ),
      ConvertAction(
        id: "chromium-markdown-screenshot",
        title: "Markdown screenshot",
        subtitle: "Capture rendered Markdown",
        icon: "text.below.photo",
        group: .chromium,
        path: "/forms/chromium/screenshot/markdown",
        urlField: false,
        files: FileSlot(
          field: "files", label: "HTML wrapper and Markdown",
          types: ConvertUTType.markdown, allowsMultiple: true,
          help:
            "Must include index.html and at least one .md file. Not office documents or PDFs.",
          extensions: ConvertUTType.markdownSources,
          mustInclude: [ConvertUTType.htmlExtensions, ConvertUTType.markdownExtensions],
          requiredNames: ["index.html"]),
        extraFiles: [],
        fields: chromiumScreenshotFields,
        output: .image,
        defaultFilename: "screenshot"
      ),
    ]

    fileprivate static let libreOffice: [ConvertAction] = [
      ConvertAction(
        id: "libreoffice-convert",
        title: "Office to PDF",
        subtitle: "DOCX, XLSX, PPTX, ODT, and more",
        icon: "doc.richtext",
        group: .libreOffice,
        path: "/forms/libreoffice/convert",
        urlField: false,
        files: FileSlot(
          field: "files", label: "Office documents", types: ConvertUTType.office,
          allowsMultiple: true,
          help:
            "Word, Excel, PowerPoint, OpenDocument, RTF, CSV. Not PDFs (Merge), HTML (HTML to PDF), or images.",
          extensions: ConvertUTType.officeExtensions),
        extraFiles: [],
        fields: libreOfficeExportFields,
        output: .pdf,
        defaultFilename: "office",
        composer: .finishing
      ),
    ]
  }

  let chromiumPDFFields: [FormField] =
    [
      toggle("landscape", "Landscape", section: "Page"),
      toggle("printBackground", "Print background", section: "Page"),
      toggle("preferCssPageSize", "Prefer CSS page size", section: "Page"),
      toggle("singlePage", "Single page", section: "Page"),
      text("scale", "Scale", default: "1.0", section: "Page", placeholder: "1.0"),
      picker("paperSize", "Paper size", paperSizeOptions, default: "", section: "Page"),
      text("paperWidth", "Paper width (in)", default: "8.5", section: "Page", placeholder: "8.5"),
      text("paperHeight", "Paper height (in)", default: "11", section: "Page", placeholder: "11"),
      text("marginTop", "Margin top (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text(
        "marginBottom", "Margin bottom (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text("marginLeft", "Margin left (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text(
        "marginRight", "Margin right (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text("nativePages", "Page ranges", section: "Page", placeholder: "1-3,5"),
      toggle("nativeBookmarks", "PDF bookmarks", section: "Page"),
      toggle("nativeTaggedPdf", "Tagged PDF", section: "Page"),
      toggle("omitBackground", "Omit background", section: "Page"),
    ] + chromiumWaitFields() + chromiumRequestFields()

  let chromiumScreenshotFields: [FormField] =
    [
      picker("format", "Format", ["png", "jpeg", "webp"], default: "png", section: "Capture"),
      text("width", "Width (px)", default: "800", section: "Capture", placeholder: "800"),
      text("height", "Height (px)", default: "600", section: "Capture", placeholder: "600"),
      text("quality", "Quality", default: "100", section: "Capture", placeholder: "1-100"),
      text(
        "deviceScaleFactor", "Device scale", default: "1.0", section: "Capture", placeholder: "1.0"),
      toggle("clip", "Clip to dimensions", section: "Capture"),
      text("selector", "CSS selector", section: "Capture"),
      toggle("optimizeForSpeed", "Optimize for speed", section: "Capture"),
      toggle("omitBackground", "Omit background", section: "Capture"),
    ] + chromiumWaitFields() + chromiumRequestFields()

#endif
