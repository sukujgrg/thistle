#if os(macOS) && arch(arm64)

  import UniformTypeIdentifiers

  extension ConvertAction {
  static let libreOfficeExportFields: [FormField] = [
    toggle("landscape", "Landscape", section: "Page"),
    text("nativePages", "Page ranges", section: "Page", placeholder: "1-3"),
    toggle("nativeBookmarks", "PDF bookmarks", default: true, section: "Page"),
    toggle("nativeTaggedPdf", "Tagged PDF", section: "Page"),
    toggle("singlePage", "Single-page sheets", section: "Page"),
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
    picker("nativePdfa", "PDF/A", pdfaOptions, default: "", section: "Export"),
    picker(
      "nativePdfua", "PDF/UA", ["", "PDF/UA-1"], default: "", section: "Export"),
    picker("initialView", "Initial view", libreOfficeInitialView, default: "default", section: "Viewer"),
    text("initialPage", "Initial page", default: "1", section: "Viewer", placeholder: "1"),
    picker(
      "magnification", "Magnification", libreOfficeMagnification, default: "default",
      section: "Viewer"),
    text("zoom", "Zoom", default: "100", section: "Viewer", placeholder: "100"),
    picker("pageLayout", "Page layout", libreOfficePageLayout, default: "default", section: "Viewer"),
    picker(
      "openBookmarkLevels", "Open bookmark levels",
      ["-1", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"], default: "-1",
      section: "Viewer"),
    toggle("resizeWindowToInitialPage", "Resize window to initial page", section: "Viewer"),
    toggle("centerWindow", "Center window", section: "Viewer"),
    toggle("openInFullScreenMode", "Open in full screen", section: "Viewer"),
    toggle("displayPDFDocumentTitle", "Display PDF title", default: true, section: "Viewer"),
    toggle("hideViewerMenubar", "Hide viewer menu bar", section: "Viewer"),
    toggle("hideViewerToolbar", "Hide viewer toolbar", section: "Viewer"),
    toggle("hideViewerWindowControls", "Hide viewer window controls", section: "Viewer"),
    toggle("useTransitionEffects", "Use transition effects", default: true, section: "Viewer"),
    text("nativeWatermarkText", "Watermark text", section: "Watermark"),
    text("nativeTiledWatermarkText", "Tiled watermark text", section: "Watermark"),
    text(
      "nativeWatermarkColor", "Watermark color", default: "#6BC36B", section: "Watermark",
      placeholder: "#rrggbb"),
    text("nativeWatermarkFontSize", "Watermark font size", section: "Watermark", placeholder: "48"),
    text("nativeWatermarkFont", "Watermark font", default: "Helvetica", section: "Watermark"),
    text("nativeWatermarkRotation", "Watermark rotation", section: "Watermark", placeholder: "45"),
    text("nativeQuality", "JPEG quality", default: "90", section: "Images", placeholder: "1-100"),
    toggle("nativeLosslessImageCompression", "Lossless images", section: "Images"),
    toggle("nativeReduceImageResolution", "Reduce image resolution", section: "Images"),
    picker(
      "nativeMaxImageResolution", "Max image DPI", ["75", "150", "300", "600", "1200"],
      default: "300", section: "Images"),
  ]

  static let pdfActions: [ConvertAction] = [
    ConvertAction(
      id: "pdf-merge", title: "Merge", subtitle: "Combine PDFs in order", icon: "square.on.square",
      group: .pdf, path: "/forms/pdf/merge", urlField: false,
      files: pdfFiles(
        "Select two or more PDFs. Order is the merge order.", multiple: true, minimumCount: 2),
      extraFiles: [], fields: [], output: .pdf, defaultFilename: "merged"),
    ConvertAction(
      id: "pdf-split", title: "Split", subtitle: "Split by intervals or ranges",
      icon: "square.split.2x1", group: .pdf, path: "/forms/pdf/split", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        picker(
          "splitMode", "Mode", ["intervals", "pages"], default: "intervals", section: "Split",
          sendDefault: true),
        text("every", "Every", default: "1", section: "Split", placeholder: "1", sendDefault: true),
        text(
          "ranges", "Ranges", section: "Split",
          placeholder: #"1-3,5 or ["1-3","5"]"#),
      ], output: .zip, defaultFilename: "split"),
    ConvertAction(
      id: "pdf-select", title: "Select pages", subtitle: "Keep only selected pages",
      icon: "doc.text.magnifyingglass", group: .pdf, path: "/forms/pdf/select", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [text("pages", "Pages", section: "Pages", placeholder: "1-3,5", sendDefault: true)],
      output: .pdf, defaultFilename: "selected"),
    ConvertAction(
      id: "pdf-delete", title: "Delete pages", subtitle: "Remove pages from a PDF",
      icon: "trash", group: .pdf, path: "/forms/pdf/delete", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [text("pages", "Pages", section: "Pages", placeholder: "2,4-5", sendDefault: true)],
      output: .pdf, defaultFilename: "deleted"),
    ConvertAction(
      id: "pdf-insert", title: "Insert PDF", subtitle: "Insert pages from another PDF",
      icon: "arrow.right.doc.on.clipboard", group: .pdf, path: "/forms/pdf/insert", urlField: false,
      files: pdfFiles("Host PDF."), extraFiles: [
        FileSlot(
          field: "insert", label: "PDF to insert", types: ConvertUTType.pdf, allowsMultiple: false,
          help: "PDF whose pages are inserted into the host.", extensions: ConvertUTType.pdfExtensions)
      ],
      fields: [
        text("at", "After page", section: "Insert", placeholder: "0"),
        text("sourcePages", "Source pages", section: "Insert", placeholder: "all"),
      ],
      output: .pdf, defaultFilename: "inserted"),
    ConvertAction(
      id: "pdf-flatten-form", title: "Flatten form", subtitle: "Flatten interactive fields",
      icon: "rectangle.compress.vertical", group: .pdf, path: "/forms/pdf/flatten-form",
      urlField: false, files: pdfFiles("Select one PDF."), extraFiles: [], fields: [],
      output: .pdf, defaultFilename: "flattened"),
    ConvertAction(
      id: "pdf-flatten-transparency", title: "Flatten transparency",
      subtitle: "Flatten transparent artwork", icon: "square.on.square.dashed",
      group: .pdf, path: "/forms/pdf/flatten-transparency", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [], fields: [], output: .pdf,
      defaultFilename: "flattened"),
    ConvertAction(
      id: "pdf-convert-colors", title: "Convert colors", subtitle: "Change device color space",
      icon: "paintpalette", group: .pdf, path: "/forms/pdf/convert-colors", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        picker("space", "Space", ["Gray", "RGB", "CMYK"], default: "RGB", section: "Color",
          sendDefault: true)
      ], output: .pdf, defaultFilename: "colors"),
    ConvertAction(
      id: "pdf-optimize", title: "Optimize", subtitle: "Shrink PDF structure and images",
      icon: "speedometer", group: .pdf, path: "/forms/pdf/optimize", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [], fields: pdfOptimizeRouteFields(),
      output: .pdf, defaultFilename: "optimized"),
    ConvertAction(
      id: "pdf-remediate", title: "Remediate", subtitle: "PDF/A, PDF/UA, or Factur-X",
      icon: "checkmark.seal", group: .pdf, path: "/forms/pdf/remediate", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [
        FileSlot(
          field: "xml", label: "Factur-X XML", types: ConvertUTType.xml, allowsMultiple: false,
          help: "Required when Profile is Factur-X.", required: false,
          extensions: ConvertUTType.xmlExtensions)
      ], fields: remediateFields(), output: .pdf, defaultFilename: "remediated"),
    ConvertAction(
      id: "pdf-validate", title: "Validate", subtitle: "Check conformance profile",
      icon: "checkmark.shield", group: .pdf, path: "/forms/pdf/validate", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        picker(
          "profile", "Profile", remediateProfiles.filter { !$0.isEmpty }, default: "PDF/A-2b",
          section: "Validate", sendDefault: true)
      ], output: .json, defaultFilename: "validate"),
    ConvertAction(
      id: "pdf-encrypt", title: "Encrypt", subtitle: "Password-protect a PDF", icon: "lock",
      group: .pdf, path: "/forms/pdf/encrypt", urlField: false, files: pdfFiles("Select one PDF."),
      extraFiles: [], fields: pdfEncryptFields(), output: .pdf, defaultFilename: "encrypted"),
    ConvertAction(
      id: "pdf-decrypt", title: "Decrypt", subtitle: "Remove encryption", icon: "lock.open",
      group: .pdf, path: "/forms/pdf/decrypt", urlField: false, files: pdfFiles("Select one PDF."),
      extraFiles: [], fields: [secure("password", "Password")], output: .pdf,
      defaultFilename: "decrypted"),
    ConvertAction(
      id: "pdf-rotate", title: "Rotate", subtitle: "Rotate pages 90, 180, or 270°",
      icon: "rotate.right", group: .pdf, path: "/forms/pdf/rotate", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        picker("angle", "Angle", ["90", "180", "270"], default: "90", sendDefault: true),
        text("pages", "Pages", section: "Pages", placeholder: "all"),
      ], output: .pdf, defaultFilename: "rotated"),
    ConvertAction(
      id: "pdf-stamp", title: "Stamp", subtitle: "Text, image, or PDF stamps",
      icon: "seal", group: .pdf, path: "/forms/pdf/pipe", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [], fields: [], output: .pdf,
      defaultFilename: "stamped", composer: .stamps),
    ConvertAction(
      id: "pdf-metadata-read", title: "Read metadata", subtitle: "PDF info as JSON",
      icon: "info.circle", group: .pdf, path: "/forms/pdf/metadata", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [], fields: [], output: .json,
      defaultFilename: "metadata"),
    ConvertAction(
      id: "pdf-metadata-write", title: "Write metadata", subtitle: "Set document info",
      icon: "pencil.and.list.clipboard", group: .pdf, path: "/forms/pdf/set-metadata",
      urlField: false, files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: pdfMetadataWriteFields(), output: .pdf, defaultFilename: "metadata"),
    ConvertAction(
      id: "pdf-bookmarks-read", title: "Read bookmarks", subtitle: "Outline as JSON",
      icon: "bookmark", group: .pdf, path: "/forms/pdf/bookmarks", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [], fields: [], output: .json,
      defaultFilename: "bookmarks"),
    ConvertAction(
      id: "pdf-bookmarks-write", title: "Write bookmarks", subtitle: "Replace outline",
      icon: "bookmark.fill", group: .pdf, path: "/forms/pdf/set-bookmarks", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        multiline(
          "bookmarks", "Bookmarks JSON", default: #"[{"title":"Chapter 1","pageNumber":1}]"#,
          sendDefault: true)
      ], output: .pdf, defaultFilename: "bookmarks"),
    ConvertAction(
      id: "pdf-attach", title: "Attach files", subtitle: "Embed attachments",
      icon: "paperclip", group: .pdf, path: "/forms/pdf/pipe", urlField: false,
      files: pdfFiles("Host PDF."), extraFiles: [
        FileSlot(
          field: "attachments", label: "Attachments", types: ConvertUTType.any,
          allowsMultiple: true,
          help: "One or more files to attach. Order becomes attach stages.", minimumCount: 1)
      ], fields: [], output: .pdf, defaultFilename: "attached"),
    ConvertAction(
      id: "pdf-detach", title: "Detach", subtitle: "Remove one attachment",
      icon: "paperclip.badge.ellipsis", group: .pdf, path: "/forms/pdf/detach", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [text("name", "Attachment name", section: "Attachment", sendDefault: true)],
      output: .pdf, defaultFilename: "detached"),
    ConvertAction(
      id: "pdf-extract-attachments", title: "Extract attachments", subtitle: "Attachments as ZIP",
      icon: "tray.and.arrow.down", group: .pdf, path: "/forms/pdf/extract-attachments",
      urlField: false, files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [text("name", "Name", section: "Attachment")], output: .zip,
      defaultFilename: "attachments"),
    ConvertAction(
      id: "pdf-extract-text", title: "Extract text", subtitle: "Text per page",
      icon: "doc.plaintext", group: .pdf, path: "/forms/pdf/extract-text", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        text("pages", "Pages", section: "Extract"),
        toggle("invisible", "Invisible text", section: "Extract"),
        toggle("artifacts", "Artifacts", section: "Extract"),
        toggle("annotations", "Annotations", section: "Extract"),
      ], output: .zip, defaultFilename: "text"),
    ConvertAction(
      id: "pdf-set-form", title: "Set form fields", subtitle: "Fill AcroForm fields",
      icon: "list.bullet.rectangle", group: .pdf, path: "/forms/pdf/set-form", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        multiline(
          "fields", "Fields JSON", default: #"[{"name":"field1","value":"Yes"}]"#,
          sendDefault: true)
      ], output: .pdf, defaultFilename: "form"),
    ConvertAction(
      id: "pdf-form-read", title: "Read form", subtitle: "AcroForm fields as JSON",
      icon: "list.bullet", group: .pdf, path: "/forms/pdf/form", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [], fields: [], output: .json,
      defaultFilename: "form"),
    ConvertAction(
      id: "pdf-redact", title: "Redact", subtitle: "Remove regions",
      icon: "eye.slash", group: .pdf, path: "/forms/pdf/redact", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        multiline(
          "regions", "Regions JSON",
          default: #"[{"page":1,"x":0,"y":0,"width":100,"height":20}]"#, sendDefault: true)
      ], output: .pdf, defaultFilename: "redacted"),
    ConvertAction(
      id: "pdf-autotag", title: "Autotag", subtitle: "Add structure tags", icon: "tag",
      group: .pdf, path: "/forms/pdf/autotag", urlField: false, files: pdfFiles("Select one PDF."),
      extraFiles: [], fields: [], output: .pdf, defaultFilename: "tagged"),
    ConvertAction(
      id: "pdf-sign", title: "Sign", subtitle: "Digital signature", icon: "signature",
      group: .pdf, path: "/forms/pdf/sign", urlField: false, files: pdfFiles("Select one PDF."),
      extraFiles: [
        FileSlot(
          field: "certificate", label: "Certificate", types: [.data], allowsMultiple: false,
          help: "PKCS#12 (.p12/.pfx) or PEM certificate. Uploaded with the PDF under files.",
          minimumCount: 1, extensions: ["p12", "pfx", "pem", "crt"]),
        FileSlot(
          field: "key", label: "Private key", types: [.data], allowsMultiple: false,
          help: "PEM private key when the certificate is PEM. Leave empty for PKCS#12.",
          minimumCount: 0, required: false, extensions: ["pem", "key"]),
      ],
      fields: [
        secure("certificatePassword", "Certificate password", section: "Signature"),
        toggle("pades", "PAdES (eIDAS)", section: "Signature"),
        text("reason", "Reason", section: "Signature"),
        text("location", "Location", section: "Signature"),
        text("name", "Signer name", section: "Signature"),
        text("contactInfo", "Contact", section: "Signature"),
        text("timestampUrl", "Timestamp URL", section: "Signature",
          placeholder: "https://timestamp.example"),
      ], output: .pdf, defaultFilename: "signed"),
    ConvertAction(
      id: "pdf-timestamp", title: "Timestamp", subtitle: "RFC 3161 timestamp",
      icon: "clock", group: .pdf, path: "/forms/pdf/timestamp", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [text("url", "TSA URL", section: "Timestamp", sendDefault: true)], output: .pdf,
      defaultFilename: "timestamped"),
    ConvertAction(
      id: "pdf-render", title: "Render pages", subtitle: "Rasterize to PNG or JPEG",
      icon: "photo", group: .pdf, path: "/forms/pdf/render", urlField: false,
      files: pdfFiles("Select one PDF."), extraFiles: [],
      fields: [
        picker("format", "Format", ["png", "jpeg"], default: "png", section: "Render",
          sendDefault: true),
        text("dpi", "DPI", default: "150", section: "Render"),
        text("pages", "Pages", section: "Render"),
      ], output: .zip, defaultFilename: "render"),
    ConvertAction(
      id: "pdf-compose", title: "Compose", subtitle: "Place PDFs on a sheet",
      icon: "square.grid.3x3", group: .pdf, path: "/forms/pdf/compose", urlField: false,
      files: pdfFiles("PDFs to place.", multiple: true, minimumCount: 1), extraFiles: [],
      fields: [
        picker("paperSize", "Paper size", paperSizeOptions, default: "A4", section: "Compose",
          sendDefault: true),
        multiline(
          "placements", "Placements JSON", section: "Compose",
          placeholder: #"[{"file":"doc.pdf","x":0,"y":0}]"#, sendDefault: true),
      ], output: .pdf, defaultFilename: "composed"),
  ]
  }

#endif
