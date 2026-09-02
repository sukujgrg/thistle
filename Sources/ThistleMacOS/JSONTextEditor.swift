#if os(macOS) && arch(arm64)

  import AppKit
  import SwiftUI

  struct JSONTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
      let textStorage = NSTextStorage()
      let layoutManager = NSLayoutManager()
      textStorage.addLayoutManager(layoutManager)

      let textContainer = NSTextContainer(
        size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
      textContainer.widthTracksTextView = true
      textContainer.lineFragmentPadding = 0
      layoutManager.addTextContainer(textContainer)

      let textView = JSONTextView(frame: .zero, textContainer: textContainer)
      textView.delegate = context.coordinator
      textView.minSize = NSSize(width: 0, height: 0)
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.autoresizingMask = [.width]
      textView.string = text
      textView.applyPlainTextBehavior()
      textView.isEditable = isEditable
      JSONHighlighter.apply(to: textView)

      let scrollView = NSScrollView()
      scrollView.drawsBackground = false
      scrollView.backgroundColor = .clear
      scrollView.borderType = .noBorder
      scrollView.hasVerticalScroller = true
      scrollView.hasHorizontalScroller = false
      scrollView.autohidesScrollers = true
      scrollView.documentView = textView
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      context.coordinator.parent = self
      guard let textView = scrollView.documentView as? JSONTextView else { return }
      textView.lockPlainTextInput()
      textView.isEditable = isEditable
      textView.isSelectable = true
      if textView.string != text {
        context.coordinator.isApplying = true
        textView.string = text
        context.coordinator.isApplying = false
      }
      JSONHighlighter.apply(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
      var parent: JSONTextEditor
      var isApplying = false

      init(_ parent: JSONTextEditor) {
        self.parent = parent
      }

      func textDidChange(_ notification: Notification) {
        guard !isApplying, let textView = notification.object as? JSONTextView else { return }
        parent.text = textView.string
        JSONHighlighter.apply(to: textView)
      }
    }
  }

  final class JSONTextView: NSTextView {
    static var monoFont: NSFont {
      NSFont.monospacedSystemFont(
        ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
        weight: .regular
      )
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
      super.init(frame: frameRect, textContainer: container)
      applyPlainTextBehavior()
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      applyPlainTextBehavior()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      lockPlainTextInput()
    }

    override func becomeFirstResponder() -> Bool {
      let result = super.becomeFirstResponder()
      lockPlainTextInput()
      return result
    }

    override func viewDidChangeEffectiveAppearance() {
      super.viewDidChangeEffectiveAppearance()
      JSONHighlighter.apply(to: self)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func paste(_ sender: Any?) {
      pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
      pasteAsPlainText(sender)
    }

    override func changeFont(_ sender: Any?) {}
    override func changeAttributes(_ sender: Any?) {}

    override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
      isAutomaticQuoteSubstitutionEnabled = false
    }

    override func toggleAutomaticDashSubstitution(_ sender: Any?) {
      isAutomaticDashSubstitutionEnabled = false
    }

    override func toggleAutomaticTextReplacement(_ sender: Any?) {
      isAutomaticTextReplacementEnabled = false
    }

    override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
      isAutomaticSpellingCorrectionEnabled = false
    }

    override func toggleSmartInsertDelete(_ sender: Any?) {
      smartInsertDeleteEnabled = false
    }

    func applyPlainTextBehavior() {
      drawsBackground = false
      allowsUndo = true
      isRichText = true
      importsGraphics = false
      allowsImageEditing = false
      usesFontPanel = false
      usesRuler = false
      usesAdaptiveColorMappingForDarkAppearance = false
      insertionPointColor = .labelColor
      textContainerInset = .zero
      lockPlainTextInput()
    }

    func lockPlainTextInput() {
      isAutomaticQuoteSubstitutionEnabled = false
      isAutomaticDashSubstitutionEnabled = false
      isAutomaticTextReplacementEnabled = false
      isAutomaticSpellingCorrectionEnabled = false
      isAutomaticDataDetectionEnabled = false
      isAutomaticLinkDetectionEnabled = false
      isAutomaticTextCompletionEnabled = false
      isContinuousSpellCheckingEnabled = false
      isGrammarCheckingEnabled = false
      smartInsertDeleteEnabled = false
      enabledTextCheckingTypes = 0
      typingAttributes = [
        .font: Self.monoFont,
        .foregroundColor: NSColor.labelColor,
      ]
    }
  }

  enum JSONHighlighter {
    @MainActor
    static func apply(to textView: NSTextView) {
      guard let storage = textView.textStorage else { return }
      let font = JSONTextView.monoFont
      let ns = storage.string as NSString
      let full = NSRange(location: 0, length: ns.length)
      let undo = textView.undoManager
      undo?.disableUndoRegistration()
      storage.beginEditing()
      storage.setAttributes(
        [
          .font: font,
          .foregroundColor: NSColor.labelColor,
        ], range: full)
      for token in JSONLexer.tokens(in: storage.string) {
        storage.addAttributes(
          [
            .font: font,
            .foregroundColor: color(for: token.kind),
          ], range: token.range)
      }
      storage.endEditing()
      undo?.enableUndoRegistration()
      textView.typingAttributes = [
        .font: font,
        .foregroundColor: NSColor.labelColor,
      ]
    }

    private static func color(for kind: JSONLexer.Kind) -> NSColor {
      switch kind {
      case .key: .systemTeal
      case .string: .systemGreen
      case .number: .systemPurple
      case .keyword: .systemOrange
      case .punctuation: .secondaryLabelColor
      case .invalid: .systemRed
      }
    }
  }

  struct JSONLexer {
    enum Kind {
      case key
      case string
      case number
      case keyword
      case punctuation
      case invalid
    }

    struct Token {
      var kind: Kind
      var range: NSRange
    }

    private enum Frame {
      case object(expectKey: Bool)
      case array
    }

    private let units: [UInt16]
    private var i = 0
    private var stack: [Frame] = []
    private var tokens: [Token] = []

    static func tokens(in string: String) -> [Token] {
      var lexer = JSONLexer(units: Array(string.utf16))
      lexer.scan()
      return lexer.tokens
    }

    private mutating func scan() {
      while i < units.count {
        let c = units[i]
        if isWhitespace(c) {
          i += 1
          continue
        }
        switch c {
        case 0x7B:
          emit(.punctuation, from: i, length: 1)
          stack.append(.object(expectKey: true))
          i += 1
        case 0x7D:
          emit(.punctuation, from: i, length: 1)
          pop()
          i += 1
        case 0x5B:
          emit(.punctuation, from: i, length: 1)
          stack.append(.array)
          i += 1
        case 0x5D:
          emit(.punctuation, from: i, length: 1)
          pop()
          i += 1
        case 0x3A:
          emit(.punctuation, from: i, length: 1)
          setExpectKey(false)
          i += 1
        case 0x2C:
          emit(.punctuation, from: i, length: 1)
          setExpectKey(true)
          i += 1
        case 0x22:
          scanString()
        default:
          if c == 0x2D || isDigit(c) {
            scanNumber()
          } else if isAlpha(c) {
            scanKeyword()
          } else {
            emit(.invalid, from: i, length: 1)
            i += 1
          }
        }
      }
    }

    private mutating func scanString() {
      let start = i
      i += 1
      while i < units.count {
        let c = units[i]
        if c == 0x5C {
          i += i + 1 < units.count ? 2 : 1
          continue
        }
        if c == 0x22 {
          i += 1
          emit(expectingKey ? .key : .string, from: start, length: i - start)
          if expectingKey {
            setExpectKey(false)
          }
          return
        }
        i += 1
      }
      emit(expectingKey ? .key : .string, from: start, length: i - start)
    }

    private mutating func scanNumber() {
      let start = i
      if units[i] == 0x2D {
        i += 1
      }
      guard i < units.count, isDigit(units[i]) else {
        emit(.invalid, from: start, length: max(1, i - start))
        return
      }
      if units[i] == 0x30 {
        i += 1
      } else {
        while i < units.count, isDigit(units[i]) { i += 1 }
      }
      if i < units.count, units[i] == 0x2E {
        i += 1
        guard i < units.count, isDigit(units[i]) else {
          emit(.invalid, from: start, length: i - start)
          return
        }
        while i < units.count, isDigit(units[i]) { i += 1 }
      }
      if i < units.count, units[i] == 0x65 || units[i] == 0x45 {
        i += 1
        if i < units.count, units[i] == 0x2B || units[i] == 0x2D { i += 1 }
        guard i < units.count, isDigit(units[i]) else {
          emit(.invalid, from: start, length: i - start)
          return
        }
        while i < units.count, isDigit(units[i]) { i += 1 }
      }
      emit(.number, from: start, length: i - start)
    }

    private mutating func scanKeyword() {
      let start = i
      while i < units.count, isAlpha(units[i]) { i += 1 }
      let word = String(utf16CodeUnits: Array(units[start..<i]), count: i - start)
      let kind: Kind =
        word == "true" || word == "false" || word == "null" ? .keyword : .invalid
      emit(kind, from: start, length: i - start)
    }

    private mutating func emit(_ kind: Kind, from location: Int, length: Int) {
      guard length > 0 else { return }
      tokens.append(Token(kind: kind, range: NSRange(location: location, length: length)))
    }

    private mutating func pop() {
      if !stack.isEmpty { stack.removeLast() }
    }

    private mutating func setExpectKey(_ value: Bool) {
      guard case .object = stack.last else { return }
      stack[stack.count - 1] = .object(expectKey: value)
    }

    private var expectingKey: Bool {
      if case .object(let expectKey) = stack.last { return expectKey }
      return false
    }

    private func isWhitespace(_ c: UInt16) -> Bool {
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    private func isDigit(_ c: UInt16) -> Bool {
      c >= 0x30 && c <= 0x39
    }

    private func isAlpha(_ c: UInt16) -> Bool {
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }
  }

#endif
