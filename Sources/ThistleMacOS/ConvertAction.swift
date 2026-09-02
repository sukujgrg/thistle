#if os(macOS) && arch(arm64)

  import Foundation
  import UniformTypeIdentifiers

  enum ActionGroup: String, CaseIterable, Identifiable {
    case chromium = "Chromium"
    case libreOffice = "LibreOffice"
    case pdfEngines = "PDF Engines"

    var id: String { rawValue }
  }

  enum ActionOutput: Hashable {
    case pdf
    case image
    case json
    case zipOrPdf
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
        return "'\(filename)' is a PDF. Use Merge or another PDF Engine action."
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

    var runTitle: String {
      switch output {
      case .json:
        "Read"
      case .image:
        "Capture"
      case .pdf:
        group == .pdfEngines ? title : "Convert to PDF"
      case .zipOrPdf:
        title
      }
    }

    var outputExtension: String? {
      switch output {
      case .pdf, .zipOrPdf: "pdf"
      case .json: "json"
      case .image: nil
      }
    }

    static let all: [ConvertAction] = chromium + libreOffice + pdfEngines

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

  private enum FieldHelp {
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
      "singlePage": Entry(text: "Fit the whole document on one PDF page."),
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
      "nativePageRanges": Entry(
        text: "Pages to print, e.g. 1-5, 8, 11-13. Empty means every page.", caption: true),
      "generateDocumentOutline": Entry(
        text: "Embed a PDF outline from headings. Chromium also turns on tagged PDF.", caption: true
      ),
      "generateTaggedPdf": Entry(
        text:
          "Build an accessible tagged PDF in Chromium. Prefer this over PDF/UA for HTML and URL conversions.",
        caption: true),
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
      "waitWindowStatus": Entry(
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
      "pdfa": Entry(
        text: "Convert the result to a PDF/A archival profile. Empty leaves the PDF as written."),
      "pdfua": Entry(
        text: "LibreOffice post-process for PDF/UA. Slower. For Chromium, prefer Tagged PDF.",
        caption: true),
      "optimizeImages": Entry(text: "Recompress images in the PDF to shrink the file."),
      "imageQuality": Entry(
        text: "JPEG quality from 1 to 100 when optimizing images. Higher is larger."),
      "splitMode": Entry(
        text: "intervals repeats every N pages. pages uses Span as a page list.", caption: true),
      "splitSpan": Entry(
        text: "With intervals, a count such as 1. With pages, a range such as 1-3.", caption: true),
      "splitUnify": Entry(
        text: "After splitting, merge the parts back into one PDF.", caption: true),
      "userPassword": Entry(
        text: "Password required to open the PDF. Leave empty for owner-only encryption."),
      "ownerPassword": Entry(
        text: "Password for changing permissions. One of the two passwords is required to encrypt."),
      "allowPrinting": Entry(text: "Allow printing when the user password is used."),
      "allowCopying": Entry(text: "Allow copying text and images."),
      "allowModifying": Entry(text: "Allow changing page content."),
      "allowAnnotating": Entry(text: "Allow comments and markup."),
      "allowFillingForms": Entry(text: "Allow filling interactive form fields."),
      "allowAssembling": Entry(
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
      "singlePageSheets": Entry(
        text: "Put every spreadsheet sheet on exactly one page, including hidden sheets.",
        caption: true),
      "nativePdfFormats": Entry(
        text:
          "Let LibreOffice write PDF/A and PDF/UA itself. Off uses the PDF Engines pass, which also runs when you split or encrypt.",
        caption: true),
      "initialView": Entry(
        text: "What the PDF viewer shows on open: none, outline pane, or thumbnails."),
      "initialPage": Entry(text: "Page shown when the PDF opens."),
      "magnification": Entry(
        text: "Open zoom. Use zoom applies the Zoom field.", caption: true),
      "zoom": Entry(text: "Open zoom percent. Used when Magnification is Use zoom."),
      "pageLayout": Entry(text: "Page layout when the PDF opens."),
      "openBookmarkLevels": Entry(
        text: "How many outline levels are expanded. All opens every level."),
      "firstPageOnLeft": Entry(text: "With two-column layout, put page 1 on the left."),
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
        text: "Decimal RGB long. Default 8388223 is light green.", caption: true),
      "nativeWatermarkFontHeight": Entry(text: "Watermark font size."),
      "nativeWatermarkRotateAngle": Entry(
        text: "Rotation in tenths of a degree. 450 is 45 degrees.", caption: true),
      "nativeWatermarkFontName": Entry(text: "Watermark font. Default is Helvetica."),
      "quality": Entry(text: "JPEG quality from 1 to 100. Higher is larger."),
      "losslessImageCompression": Entry(text: "Export images as lossless PNG instead of JPEG."),
      "reduceImageResolution": Entry(text: "Downsample images to Max image DPI."),
      "maxImageResolution": Entry(text: "Target DPI when Reduce image resolution is on."),
      "merge": Entry(text: "Combine every converted office file into one PDF."),
      "flatten": Entry(
        text: "Flatten annotations and form fields into page content.", caption: true),
      "metadata": Entry(text: "JSON object of PDF info keys such as Title and Author."),
      "bookmarks": Entry(text: "JSON array of outline entries with title and page. Children nest."),
      "autoIndexBookmarks": Entry(
        text: "Keep each input PDF's outline after merge, shifted to the new page numbers.",
        caption: true),
      "titleBookmarks": Entry(
        text: "Nest each file's outline under a bookmark named after that file.", caption: true),
      "rotateAngle": Entry(text: "Clockwise rotation in degrees."),
      "rotatePages": Entry(
        text: "Pages to rotate, e.g. 1-3. Empty rotates every page.", caption: true),
      "watermarkSource": Entry(text: "Draw text, an image, or a PDF behind page content."),
      "watermarkExpression": Entry(text: "Watermark text when Source is text."),
      "watermarkPages": Entry(text: "Pages to mark, e.g. 1-3. Empty means every page."),
      "watermarkOptions": Entry(
        text: "QPDF overlay JSON. Common keys: scale, rot, fillcolor, op (opacity).", caption: true),
      "stampSource": Entry(text: "Draw text, an image, or a PDF on top of page content."),
      "stampExpression": Entry(text: "Stamp text when Source is text."),
      "stampPages": Entry(text: "Pages to stamp, e.g. 1-3. Empty means every page."),
      "stampOptions": Entry(
        text: "QPDF overlay JSON. Common keys: scale, rot, fillcolor, op (opacity).", caption: true),
      "embedsMetadata": Entry(
        text: "JSON object keyed by attachment filename with mimeType and relationship.",
        caption: true),
      "facturxConformanceLevel": Entry(text: "Factur-X / ZUGFeRD profile written into the XMP."),
      "facturxDocumentType": Entry(text: "Business document type stored in the XMP."),
      "facturxVersion": Entry(text: "Factur-X specification version, e.g. 1.0."),
      "format": Entry(text: "Screenshot image format."),
      "width": Entry(text: "Capture width and height in CSS pixels."),
      "height": Entry(text: "Capture height in CSS pixels."),
      "deviceScaleFactor": Entry(text: "Device pixel ratio. 2× is a Retina-density capture."),
      "clip": Entry(text: "Clip the screenshot to Width and Height instead of the full page."),
      "selector": Entry(text: "Capture only the first element that matches this CSS selector."),
      "optimizeForSpeed": Entry(text: "Faster encode with a larger file."),
    ]
  }

  private func text(
    _ key: String, _ label: String, default defaultValue: String = "", section: String = "Options",
    placeholder: String = "", sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .text, defaultValue: defaultValue, section: section,
      placeholder: placeholder, sendDefault: sendDefault, help: FieldHelp.text(key),
      showsCaption: FieldHelp.showsCaption(key))
  }

  private func secure(_ key: String, _ label: String, section: String = "Options") -> FormField {
    FormField(
      key: key, label: label, kind: .secure, defaultValue: "", section: section,
      help: FieldHelp.text(key), showsCaption: FieldHelp.showsCaption(key))
  }

  private func toggle(
    _ key: String, _ label: String, default defaultValue: Bool = false, section: String = "Options"
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .toggle, defaultValue: defaultValue ? "true" : "false",
      section: section, help: FieldHelp.text(key), showsCaption: FieldHelp.showsCaption(key))
  }

  private func picker(
    _ key: String, _ label: String, _ options: [String], default defaultValue: String,
    section: String = "Options", sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .picker(options), defaultValue: defaultValue, section: section,
      sendDefault: sendDefault, help: FieldHelp.text(key), showsCaption: FieldHelp.showsCaption(key)
    )
  }

  private func multiline(
    _ key: String, _ label: String, default defaultValue: String = "", section: String = "Options",
    placeholder: String = "", sendDefault: Bool = false
  ) -> FormField {
    FormField(
      key: key, label: label, kind: .multiline, defaultValue: defaultValue, section: section,
      placeholder: placeholder, sendDefault: sendDefault, help: FieldHelp.text(key),
      showsCaption: FieldHelp.showsCaption(key))
  }

  // Values from pkg/gotenberg/pdfengine.go. Bruno only listed *-b.
  private let pdfaOptions = [
    "", "PDF/A-1a", "PDF/A-1b", "PDF/A-2a", "PDF/A-2b", "PDF/A-2u", "PDF/A-3a", "PDF/A-3b",
    "PDF/A-3u",
  ]

  private func pdfArchiveFields(section: String = "PDF") -> [FormField] {
    [
      picker("pdfa", "PDF/A", pdfaOptions, default: "", section: section),
      toggle("pdfua", "PDF/UA", section: section),
    ]
  }

  private func pdfOptimizeFields(section: String = "PDF") -> [FormField] {
    [
      toggle("optimizeImages", "Optimize images", section: section),
      text("imageQuality", "Image quality", section: section, placeholder: "1-100"),
    ]
  }

  private func pdfSplitFields(section: String = "Split") -> [FormField] {
    [
      picker("splitMode", "Split mode", ["", "intervals", "pages"], default: "", section: section),
      text("splitSpan", "Split span", section: section, placeholder: "1 or 1-3"),
      toggle("splitUnify", "Unify into one PDF", section: section),
    ]
  }

  private func pdfEncryptFields(section: String = "Encryption") -> [FormField] {
    [
      secure("userPassword", "User password", section: section),
      secure("ownerPassword", "Owner password", section: section),
      toggle("allowPrinting", "Allow printing", default: true, section: section),
      toggle("allowCopying", "Allow copying", default: true, section: section),
      toggle("allowModifying", "Allow modifying", default: true, section: section),
      toggle("allowAnnotating", "Allow annotating", default: true, section: section),
      toggle("allowFillingForms", "Allow filling forms", default: true, section: section),
      toggle("allowAssembling", "Allow assembling", default: true, section: section),
    ]
  }

  // FormDataChromiumOptions in pkg/modules/chromium/routes.go.
  private func chromiumWaitFields() -> [FormField] {
    [
      text("waitDelay", "Wait delay", section: "Wait", placeholder: "0s"),
      text("waitForSelector", "Wait for selector", section: "Wait"),
      text("waitForExpression", "Wait for expression", section: "Wait"),
      text("waitWindowStatus", "Wait for window status", section: "Wait"),
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

  private func chromiumRequestFields(mediaTypeDefault: String = "") -> [FormField] {
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

  private func pdfFiles(_ help: String, multiple: Bool = false, minimumCount: Int = 1) -> FileSlot {
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
        defaultFilename: "page"
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
        defaultFilename: "document"
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
        defaultFilename: "markdown"
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
        fields: [
          toggle("landscape", "Landscape", section: "Page"),
          text(
            "nativePageRanges", "Page ranges", section: "Page", placeholder: "1-3"),
          secure("password", "Document password", section: "Page"),
          toggle("updateIndexes", "Update indexes", default: true, section: "Export"),
          toggle("exportBookmarks", "Export bookmarks", default: true, section: "Export"),
          toggle(
            "exportBookmarksToPdfDestination", "Export bookmarks as PDF destinations",
            section: "Export"),
          toggle("exportFormFields", "Export form fields", default: true, section: "Export"),
          toggle("allowDuplicateFieldNames", "Allow duplicate field names", section: "Export"),
          toggle("exportPlaceholders", "Export placeholders", section: "Export"),
          toggle("exportNotes", "Export notes", section: "Export"),
          toggle("exportNotesPages", "Export notes pages", section: "Export"),
          toggle("exportOnlyNotesPages", "Export only notes pages", section: "Export"),
          toggle("exportNotesInMargin", "Export notes in margin", section: "Export"),
          toggle(
            "convertOooTargetToPdfTarget", "Convert OOo targets to PDF targets", section: "Export"),
          toggle("exportLinksRelativeFsys", "Export relative filesystem links", section: "Export"),
          toggle("exportHiddenSlides", "Export hidden slides", section: "Export"),
          toggle("skipEmptyPages", "Skip empty pages", section: "Export"),
          toggle("addOriginalDocumentAsStream", "Add original as stream", section: "Export"),
          toggle("singlePageSheets", "Single-page sheets", section: "Export"),
          toggle("nativePdfFormats", "Native PDF formats", default: true, section: "Export"),
          picker("initialView", "Initial view", ["0", "1", "2"], default: "0", section: "Viewer"),
          text("initialPage", "Initial page", default: "1", section: "Viewer", placeholder: "1"),
          picker(
            "magnification", "Magnification", ["0", "1", "2", "3", "4"], default: "0",
            section: "Viewer"),
          text("zoom", "Zoom", default: "100", section: "Viewer", placeholder: "100"),
          picker(
            "pageLayout", "Page layout", ["0", "1", "2", "3"], default: "0", section: "Viewer"),
          picker(
            "openBookmarkLevels", "Open bookmark levels",
            ["-1", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"], default: "-1",
            section: "Viewer"),
          toggle("firstPageOnLeft", "First page on left", section: "Viewer"),
          toggle("resizeWindowToInitialPage", "Resize window to initial page", section: "Viewer"),
          toggle("centerWindow", "Center window", section: "Viewer"),
          toggle("openInFullScreenMode", "Open in full screen", section: "Viewer"),
          toggle("displayPDFDocumentTitle", "Display PDF title", default: true, section: "Viewer"),
          toggle("hideViewerMenubar", "Hide viewer menu bar", section: "Viewer"),
          toggle("hideViewerToolbar", "Hide viewer toolbar", section: "Viewer"),
          toggle("hideViewerWindowControls", "Hide viewer window controls", section: "Viewer"),
          toggle(
            "useTransitionEffects", "Use transition effects", default: true, section: "Viewer"),
          text("nativeWatermarkText", "Native watermark text", section: "Native watermark"),
          text(
            "nativeTiledWatermarkText", "Native tiled watermark text", section: "Native watermark"),
          text("nativeWatermarkColor", "Native watermark color", section: "Native watermark"),
          text(
            "nativeWatermarkFontHeight", "Native watermark font height",
            section: "Native watermark"),
          text(
            "nativeWatermarkRotateAngle", "Native watermark angle", section: "Native watermark"),
          text("nativeWatermarkFontName", "Native watermark font", section: "Native watermark"),
          text("quality", "JPEG quality", default: "90", section: "Images", placeholder: "1-100"),
          toggle("losslessImageCompression", "Lossless images", section: "Images"),
          toggle("reduceImageResolution", "Reduce image resolution", section: "Images"),
          picker(
            "maxImageResolution", "Max image DPI", ["75", "150", "300", "600", "1200"],
            default: "300", section: "Images"),
          toggle("merge", "Merge into one PDF", section: "PDF"),
          toggle("flatten", "Flatten", section: "PDF"),
          multiline(
            "metadata", "Metadata JSON", section: "PDF",
            placeholder: #"{"Title":"","Author":""}"#),
        ] + pdfArchiveFields() + pdfOptimizeFields() + pdfSplitFields() + pdfEncryptFields(),
        output: .pdf,
        defaultFilename: "office"
      )
    ]

    fileprivate static let pdfEngines: [ConvertAction] = [
      ConvertAction(
        id: "pdf-merge",
        title: "Merge",
        subtitle: "Combine PDFs in order",
        icon: "square.on.square",
        group: .pdfEngines,
        path: "/forms/pdfengines/merge",
        urlField: false,
        files: pdfFiles(
          "Select two or more PDFs. Order is the merge order. Not office documents or images.",
          multiple: true, minimumCount: 2),
        extraFiles: [],
        fields: [
          toggle("flatten", "Flatten", section: "PDF"),
          toggle("autoIndexBookmarks", "Index bookmarks from files", section: "PDF"),
          toggle("titleBookmarks", "Title bookmarks", section: "PDF"),
          multiline(
            "metadata", "Metadata JSON", section: "PDF",
            placeholder: #"{"Title":"","Author":""}"#),
          multiline(
            "bookmarks", "Bookmarks JSON", section: "PDF",
            placeholder: #"[{"title":"Page 1","page":1}]"#),
        ] + pdfArchiveFields() + pdfOptimizeFields() + pdfEncryptFields(),
        output: .pdf,
        defaultFilename: "merged"
      ),
      ConvertAction(
        id: "pdf-split",
        title: "Split",
        subtitle: "Split by intervals or page ranges",
        icon: "square.split.2x1",
        group: .pdfEngines,
        path: "/forms/pdfengines/split",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [
          picker(
            "splitMode", "Mode", ["intervals", "pages"], default: "intervals", section: "Split",
            sendDefault: true),
          text(
            "splitSpan", "Span", default: "1", section: "Split", placeholder: "1 or 1-3",
            sendDefault: true),
          toggle("splitUnify", "Unify into one PDF", section: "Split"),
          toggle("flatten", "Flatten", section: "PDF"),
        ] + pdfArchiveFields() + pdfOptimizeFields() + pdfEncryptFields(),
        output: .zipOrPdf,
        defaultFilename: "split"
      ),
      ConvertAction(
        id: "pdf-flatten",
        title: "Flatten",
        subtitle: "Flatten annotations and forms",
        icon: "rectangle.compress.vertical",
        group: .pdfEngines,
        path: "/forms/pdfengines/flatten",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [],
        output: .pdf,
        defaultFilename: "flattened"
      ),
      ConvertAction(
        id: "pdf-optimize",
        title: "Optimize",
        subtitle: "Compress embedded images",
        icon: "speedometer",
        group: .pdfEngines,
        path: "/forms/pdfengines/optimize",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [
          text(
            "imageQuality", "Image quality", default: "80", placeholder: "1-100", sendDefault: true)
        ],
        output: .pdf,
        defaultFilename: "optimized"
      ),
      ConvertAction(
        id: "pdf-convert",
        title: "PDF/A and PDF/UA",
        subtitle: "Convert to an archival PDF",
        icon: "checkmark.seal",
        group: .pdfEngines,
        path: "/forms/pdfengines/convert",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [
          picker(
            "pdfa", "PDF/A", pdfaOptions, default: "PDF/A-2b", section: "PDF", sendDefault: true),
          toggle("pdfua", "PDF/UA", section: "PDF"),
        ],
        output: .pdf,
        defaultFilename: "pdfa"
      ),
      ConvertAction(
        id: "pdf-encrypt",
        title: "Encrypt",
        subtitle: "Password-protect a PDF",
        icon: "lock",
        group: .pdfEngines,
        path: "/forms/pdfengines/encrypt",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: pdfEncryptFields(),
        output: .pdf,
        defaultFilename: "encrypted"
      ),
      ConvertAction(
        id: "pdf-rotate",
        title: "Rotate",
        subtitle: "Rotate pages 90, 180, or 270 degrees",
        icon: "rotate.right",
        group: .pdfEngines,
        path: "/forms/pdfengines/rotate",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [
          picker("rotateAngle", "Angle", ["90", "180", "270"], default: "90", sendDefault: true),
          text("rotatePages", "Pages", default: ""),
        ],
        output: .pdf,
        defaultFilename: "rotated"
      ),
      ConvertAction(
        id: "pdf-watermark",
        title: "Watermark",
        subtitle: "Draws behind page content and is often hidden. Use Stamp to overlay.",
        icon: "drop",
        group: .pdfEngines,
        path: "/forms/pdfengines/watermark",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [
          FileSlot(
            field: "watermark",
            label: "Watermark file",
            types: ConvertUTType.images + ConvertUTType.pdf,
            allowsMultiple: false,
            help: "PNG, JPEG, WebP, or PDF.",
            minimumCount: 1,
            required: false,
            extensions: ConvertUTType.imageExtensions.union(ConvertUTType.pdfExtensions))
        ],
        fields: [
          picker(
            "watermarkSource", "Source", ["text", "image", "pdf"], default: "text",
            sendDefault: true),
          text("watermarkExpression", "Text", default: "CONFIDENTIAL", sendDefault: true),
          text("watermarkPages", "Pages"),
          multiline(
            "watermarkOptions",
            "Options JSON",
            default: ##"{"scale":"1 abs","rot":"45","fillcolor":"#C00000","op":"0.35"}"##,
            sendDefault: true),
        ],
        output: .pdf,
        defaultFilename: "watermarked"
      ),
      ConvertAction(
        id: "pdf-stamp",
        title: "Stamp",
        subtitle: "Draw on top of page content",
        icon: "seal",
        group: .pdfEngines,
        path: "/forms/pdfengines/stamp",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [
          FileSlot(
            field: "stamp",
            label: "Stamp file",
            types: ConvertUTType.images + ConvertUTType.pdf,
            allowsMultiple: false,
            help: "PNG, JPEG, WebP, or PDF.",
            minimumCount: 1,
            required: false,
            extensions: ConvertUTType.imageExtensions.union(ConvertUTType.pdfExtensions))
        ],
        fields: [
          picker(
            "stampSource", "Source", ["text", "image", "pdf"], default: "text", sendDefault: true),
          text("stampExpression", "Text", default: "APPROVED", sendDefault: true),
          text("stampPages", "Pages"),
          multiline(
            "stampOptions",
            "Options JSON",
            default: ##"{"scale":"1 abs","rot":"45","fillcolor":"#C00000","op":"0.35"}"##,
            sendDefault: true),
        ],
        output: .pdf,
        defaultFilename: "stamped"
      ),
      ConvertAction(
        id: "pdf-metadata-read",
        title: "Read metadata",
        subtitle: "Return PDF metadata as JSON",
        icon: "info.circle",
        group: .pdfEngines,
        path: "/forms/pdfengines/metadata/read",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [],
        output: .json,
        defaultFilename: "metadata"
      ),
      ConvertAction(
        id: "pdf-metadata-write",
        title: "Write metadata",
        subtitle: "Set title, author, and more",
        icon: "pencil.and.list.clipboard",
        group: .pdfEngines,
        path: "/forms/pdfengines/metadata/write",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [
          multiline(
            "metadata", "Metadata JSON", default: #"{"Title":"","Author":""}"#, sendDefault: true)
        ],
        output: .pdf,
        defaultFilename: "metadata"
      ),
      ConvertAction(
        id: "pdf-bookmarks-read",
        title: "Read bookmarks",
        subtitle: "Return the outline as JSON",
        icon: "bookmark",
        group: .pdfEngines,
        path: "/forms/pdfengines/bookmarks/read",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [],
        output: .json,
        defaultFilename: "bookmarks"
      ),
      ConvertAction(
        id: "pdf-bookmarks-write",
        title: "Write bookmarks",
        subtitle: "Replace the document outline",
        icon: "bookmark.fill",
        group: .pdfEngines,
        path: "/forms/pdfengines/bookmarks/write",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [],
        fields: [
          multiline(
            "bookmarks", "Bookmarks JSON", default: #"[{"title":"Chapter 1","page":1}]"#,
            sendDefault: true)
        ],
        output: .pdf,
        defaultFilename: "bookmarks"
      ),
      ConvertAction(
        id: "pdf-embed",
        title: "Embed files",
        subtitle: "Attach files to a PDF",
        icon: "paperclip",
        group: .pdfEngines,
        path: "/forms/pdfengines/embed",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [
          FileSlot(
            field: "embeds", label: "Attachments", types: ConvertUTType.any, allowsMultiple: true,
            help: "Any file to attach. The PDF above is the host document.", minimumCount: 1,
            required: true)
        ],
        fields: [
          multiline(
            "embedsMetadata", "Embeds metadata JSON",
            placeholder:
              #"{"file.xml":{"mimeType":"text/xml","relationship":"Data"}}"#)
        ],
        output: .pdf,
        defaultFilename: "embedded"
      ),
      ConvertAction(
        id: "pdf-facturx",
        title: "Factur-X",
        subtitle: "Inject Factur-X / ZUGFeRD XMP",
        icon: "building.columns",
        group: .pdfEngines,
        path: "/forms/pdfengines/factur-x",
        urlField: false,
        files: pdfFiles("Select one PDF."),
        extraFiles: [
          FileSlot(
            field: "facturxXml", label: "Invoice XML",
            types: ConvertUTType.xml, allowsMultiple: false,
            help: "CII invoice XML. Not a PDF.", minimumCount: 1, required: true,
            extensions: ConvertUTType.xmlExtensions)
        ],
        fields: [
          picker(
            "facturxConformanceLevel", "Conformance",
            ["MINIMUM", "BASIC WL", "BASIC", "EN 16931", "EXTENDED", "XRECHNUNG"],
            default: "EN 16931", sendDefault: true),
          picker(
            "facturxDocumentType", "Document type",
            ["INVOICE", "ORDER", "ORDER_RESPONSE", "ORDER_CHANGE"], default: "INVOICE",
            sendDefault: true),
          text("facturxVersion", "Version", default: "1.0", sendDefault: true),
        ],
        output: .pdf,
        defaultFilename: "factur-x"
      ),
    ]
  }

  // FormDataChromiumPdfOptions plus FormDataPdf* helpers used by the convert
  // routes. Watermark, stamp, Factur-X, embeds, and rotate are separate actions.
  private let chromiumPDFFields: [FormField] =
    [
      toggle("landscape", "Landscape", section: "Page"),
      toggle("printBackground", "Print background", section: "Page"),
      toggle("preferCssPageSize", "Prefer CSS page size", section: "Page"),
      toggle("singlePage", "Single page", section: "Page"),
      text("scale", "Scale", default: "1.0", section: "Page", placeholder: "1.0"),
      text("paperWidth", "Paper width (in)", default: "8.5", section: "Page", placeholder: "8.5"),
      text("paperHeight", "Paper height (in)", default: "11", section: "Page", placeholder: "11"),
      text("marginTop", "Margin top (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text(
        "marginBottom", "Margin bottom (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text("marginLeft", "Margin left (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text(
        "marginRight", "Margin right (in)", default: "0.39", section: "Page", placeholder: "0.39"),
      text("nativePageRanges", "Page ranges", section: "Page"),
      toggle("generateDocumentOutline", "Document outline", section: "Page"),
      toggle("generateTaggedPdf", "Tagged PDF", section: "Page"),
      toggle("omitBackground", "Omit background", section: "Page"),
    ] + chromiumWaitFields() + chromiumRequestFields() + pdfArchiveFields() + pdfOptimizeFields()
    + pdfSplitFields() + pdfEncryptFields() + [
      multiline(
        "metadata", "Metadata JSON", section: "PDF",
        placeholder: #"{"Title":"","Author":""}"#)
    ]

  // FormDataChromiumScreenshotOptions. No PDF finish fields.
  private let chromiumScreenshotFields: [FormField] =
    [
      picker("format", "Format", ["png", "jpeg", "webp"], default: "png", section: "Capture"),
      text("width", "Width (px)", default: "800", section: "Capture", placeholder: "800"),
      text("height", "Height (px)", default: "600", section: "Capture", placeholder: "600"),
      text("quality", "Quality", default: "100", section: "Capture", placeholder: "0-100"),
      text(
        "deviceScaleFactor", "Device scale", default: "1.0", section: "Capture", placeholder: "1.0"),
      toggle("clip", "Clip to dimensions", section: "Capture"),
      text("selector", "CSS selector", section: "Capture"),
      toggle("optimizeForSpeed", "Optimize for speed", section: "Capture"),
      toggle("omitBackground", "Omit background", section: "Capture"),
    ] + chromiumWaitFields() + chromiumRequestFields()

#endif
