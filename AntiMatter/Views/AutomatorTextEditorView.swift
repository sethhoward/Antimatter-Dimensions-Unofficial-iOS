//
//  AutomatorTextEditorView.swift
//  AntiMatter
//
//  UITextView-backed code editor with syntax highlighting for the Automator scripting language.
//  Uses regex-based keyword coloring on textDidChange — the language is small (~20 keywords),
//  so this is performant even at the 10k character limit.
//

import SwiftUI
import UIKit

struct AutomatorTextEditorView: UIViewRepresentable {
    @Binding var text: String
    let activeLine: Int              // -1 when not executing
    let errorLines: Set<Int>
    let followExecution: Bool
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AutomatorEditorContainer {
        let container = AutomatorEditorContainer()
        container.textView.delegate = context.coordinator
        container.textView.text = text
        context.coordinator.container = container
        context.coordinator.applyHighlighting(to: container.textView)
        container.updateLineHighlights(activeLine: activeLine, errorLines: errorLines)

        // Scroll to active line on initial creation (e.g. returning from another tab)
        if followExecution && activeLine > 0 {
            // Defer to next layout pass so textView has its final frame
            DispatchQueue.main.async {
                container.scrollToLine(activeLine)
            }
        }
        return container
    }

    func updateUIView(_ container: AutomatorEditorContainer, context: Context) {
        let textView = container.textView
        // Only update text if it changed externally (not from user typing)
        if textView.text != text && !context.coordinator.isEditing {
            let selectedRange = textView.selectedRange
            textView.text = text
            context.coordinator.applyHighlighting(to: textView)
            textView.selectedRange = selectedRange
        }
        container.updateLineHighlights(activeLine: activeLine, errorLines: errorLines)

        // Follow execution: scroll to active line
        if followExecution && activeLine > 0 {
            container.scrollToLine(activeLine)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        let parent: AutomatorTextEditorView
        weak var container: AutomatorEditorContainer?
        var isEditing = false
        private var saveWorkItem: DispatchWorkItem?

        init(parent: AutomatorTextEditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            isEditing = true
            parent.text = textView.text
            applyHighlighting(to: textView)
            container?.updateLineNumbers()

            // Debounced save (300ms)
            saveWorkItem?.cancel()
            let content = textView.text ?? ""
            let workItem = DispatchWorkItem { [weak self] in
                self?.parent.onTextChange(content)
            }
            saveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)

            DispatchQueue.main.async { self.isEditing = false }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            // Flush any pending save
            saveWorkItem?.cancel()
            parent.onTextChange(textView.text ?? "")
        }

        // UITextViewDelegate inherits UIScrollViewDelegate. UITextView fires
        // this on every contentOffset change — keep the line-number gutter
        // in sync with the text view's scroll position.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            container?.updateLineNumbers()
        }

        // MARK: - Syntax Highlighting

        func applyHighlighting(to textView: UITextView) {
            guard let text = textView.text, !text.isEmpty else { return }

            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let attributed = NSMutableAttributedString(string: text)

            // Base style: white monospace
            attributed.addAttributes([
                .foregroundColor: UIColor.white,
                .font: AutomatorEditorContainer.editorFont
            ], range: fullRange)

            // Comments: lines starting with # or //
            AutomatorSyntax.commentPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    attributed.addAttribute(.foregroundColor, value: AutomatorSyntax.commentColor, range: range)
                }
            }

            // Commands / keywords
            AutomatorSyntax.commandPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range(at: 1) {
                    // Don't override comments
                    let existingColor = attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
                    if existingColor != AutomatorSyntax.commentColor {
                        attributed.addAttribute(.foregroundColor, value: AutomatorSyntax.commandColor, range: range)
                    }
                }
            }

            // Game currencies
            AutomatorSyntax.currencyPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range(at: 1) {
                    let existingColor = attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
                    if existingColor != AutomatorSyntax.commentColor {
                        attributed.addAttribute(.foregroundColor, value: AutomatorSyntax.currencyColor, range: range)
                    }
                }
            }

            // Numbers
            AutomatorSyntax.numberPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    let existingColor = attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
                    if existingColor != AutomatorSyntax.commentColor {
                        attributed.addAttribute(.foregroundColor, value: AutomatorSyntax.numberColor, range: range)
                    }
                }
            }

            // Comparisons
            AutomatorSyntax.comparisonPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    let existingColor = attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
                    if existingColor != AutomatorSyntax.commentColor {
                        attributed.addAttribute(.foregroundColor, value: AutomatorSyntax.comparisonColor, range: range)
                    }
                }
            }

            // String literals (quoted)
            AutomatorSyntax.stringPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    let existingColor = attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
                    if existingColor != AutomatorSyntax.commentColor {
                        attributed.addAttribute(.foregroundColor, value: AutomatorSyntax.stringColor, range: range)
                    }
                }
            }

            // Preserve cursor position
            let selectedRange = textView.selectedRange
            textView.attributedText = attributed
            textView.selectedRange = selectedRange
        }
    }
}

// MARK: - Syntax Patterns

private enum AutomatorSyntax {
    static let commentColor = UIColor(red: 0.416, green: 0.600, blue: 0.333, alpha: 1)   // #6a9955
    static let commandColor = UIColor(red: 0.306, green: 0.788, blue: 0.690, alpha: 1)   // #4ec9b0
    static let currencyColor = UIColor(red: 0.773, green: 0.522, blue: 0.753, alpha: 1)  // #c586c0
    static let numberColor = UIColor(red: 0.710, green: 0.808, blue: 0.659, alpha: 1)    // #b5cea8
    static let comparisonColor = UIColor(red: 0.831, green: 0.831, blue: 0.667, alpha: 1) // #d4d4aa
    static let stringColor = UIColor(red: 0.808, green: 0.569, blue: 0.471, alpha: 1)    // #ce9178

    // Comments: # or // to end of line
    static let commentPattern = try! NSRegularExpression(pattern: "(?:^|(?<=\\n))\\s*(?:#|//).*", options: [])

    // Commands: keywords at word boundaries (case-insensitive to match web)
    static let commandPattern: NSRegularExpression = {
        let keywords = [
            "auto", "if", "else", "while", "until", "wait", "pause", "stop", "start",
            "studies", "respec", "load", "purchase", "infinity", "eternity", "reality",
            "unlock", "dilation", "ec", "notify", "define", "blob", "black hole",
            "on", "off", "nowait", "restarted", "name", "id", "preset"
        ].joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?:^|(?<=[\\s{};]))(" + keywords + ")(?=$|[\\s{};])", options: .caseInsensitive)
    }()

    // Currencies: game values
    static let currencyPattern: NSRegularExpression = {
        let currencies = [
            "am", "ip", "ep", "dt", "tp", "rm", "tt", "rg", "rep",
            "infinities", "eternities", "realities", "banked infinities",
            "pending ip", "pending ep", "pending tp", "pending rm",
            "total tt", "spent tt", "filter score", "space theorems",
            "ec\\d+ completions"
        ].joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?:^|(?<=[\\s>=<]))(" + currencies + ")(?=$|[\\s>=<;])", options: .caseInsensitive)
    }()

    // Numbers: integers, decimals, scientific notation
    static let numberPattern = try! NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?(?:e\\d+)?\\b", options: .caseInsensitive)

    // Comparisons
    static let comparisonPattern = try! NSRegularExpression(pattern: ">=|<=|>|<|==|!=", options: [])

    // String literals
    static let stringPattern = try! NSRegularExpression(pattern: "\"[^\"]*\"", options: [])
}

// MARK: - Editor Container (UITextView + Line Number Gutter)

class AutomatorEditorContainer: UIView {
    static let editorFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let lineNumberFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let gutterWidth: CGFloat = 36

    let textView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = UIColor(white: 0.06, alpha: 1)
        tv.textColor = .white
        tv.font = editorFont
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.keyboardAppearance = .dark
        tv.textContainerInset = UIEdgeInsets(top: 8, left: gutterWidth + 4, bottom: 8, right: 8)
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        return tv
    }()

    private let gutterView: LineNumberGutterView
    private let activeLineLayer = CALayer()
    private let errorLineLayer = CALayer()

    override init(frame: CGRect) {
        gutterView = LineNumberGutterView(textView: nil)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        gutterView = LineNumberGutterView(textView: nil)
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.06, alpha: 1)
        addSubview(textView)
        gutterView.textView = textView
        addSubview(gutterView)

        // Line highlight layers (behind text)
        activeLineLayer.backgroundColor = UIColor(red: 0.1, green: 0.3, blue: 0.1, alpha: 0.35).cgColor
        errorLineLayer.backgroundColor = UIColor(red: 0.4, green: 0.1, blue: 0.1, alpha: 0.35).cgColor
        activeLineLayer.isHidden = true
        errorLineLayer.isHidden = true
        textView.layer.insertSublayer(activeLineLayer, at: 0)
        textView.layer.insertSublayer(errorLineLayer, at: 0)

        // Note: scroll-driven redraws are routed through the Coordinator's
        // scrollViewDidScroll (UITextView is a UIScrollView; its delegate
        // inherits UIScrollViewDelegate). There is no Foundation notification
        // for UITextView scrolling — the previous textDidChangeNotification
        // observer fired on edits only, leaving line numbers static while
        // panning. Edit-driven redraws still flow through textViewDidChange →
        // updateLineNumbers().
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        // Gutter is a sibling of textView in this container's coordinate
        // space — the container does not scroll, so the gutter frame is
        // pinned to (0, 0). Per-line vertical positioning happens inside
        // draw(_:) by subtracting textView.contentOffset.y.
        gutterView.frame = CGRect(
            x: 0, y: 0,
            width: Self.gutterWidth, height: bounds.height
        )
        gutterView.setNeedsDisplay()
    }

    func updateLineNumbers() {
        gutterView.setNeedsDisplay()
    }

    func updateLineHighlights(activeLine: Int, errorLines: Set<Int>) {
        let lm = textView.layoutManager
        guard textView.text != nil, !textView.text.isEmpty else {
            activeLineLayer.isHidden = true
            errorLineLayer.isHidden = true
            return
        }

        if activeLine > 0 {
            if let rect = lineRect(forLine: activeLine, layoutManager: lm) {
                activeLineLayer.frame = rect
                activeLineLayer.isHidden = false
            } else {
                activeLineLayer.isHidden = true
            }
        } else {
            activeLineLayer.isHidden = true
        }

        // Show first error line highlight
        if let firstError = errorLines.sorted().first,
           let rect = lineRect(forLine: firstError, layoutManager: lm) {
            errorLineLayer.frame = rect
            errorLineLayer.isHidden = false
        } else {
            errorLineLayer.isHidden = true
        }
    }

    func scrollToLine(_ line: Int) {
        let lm = textView.layoutManager
        if let rect = lineRect(forLine: line, layoutManager: lm) {
            let visibleRect = CGRect(
                x: 0, y: rect.origin.y - 40,
                width: textView.bounds.width, height: rect.height + 80
            )
            textView.scrollRectToVisible(visibleRect, animated: false)
        }
    }

    private func lineRect(forLine line: Int, layoutManager lm: NSLayoutManager) -> CGRect? {
        let text = textView.text ?? ""
        guard !text.isEmpty else { return nil }

        let nsText = text as NSString
        var currentLine = 1
        var searchStart = 0

        while currentLine < line && searchStart < nsText.length {
            let range = nsText.range(of: "\n", options: [], range: NSRange(location: searchStart, length: nsText.length - searchStart))
            if range.location == NSNotFound { break }
            searchStart = range.location + 1
            currentLine += 1
        }

        if currentLine != line { return nil }

        let lineEnd: Int
        let nextNewline = nsText.range(of: "\n", options: [], range: NSRange(location: searchStart, length: nsText.length - searchStart))
        if nextNewline.location == NSNotFound {
            lineEnd = nsText.length
        } else {
            lineEnd = nextNewline.location
        }

        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: searchStart, length: lineEnd - searchStart), actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
        rect.origin.x = 0
        rect.size.width = textView.bounds.width
        rect.origin.y += textView.textContainerInset.top
        return rect
    }
}

// MARK: - Line Number Gutter

private class LineNumberGutterView: UIView {
    weak var textView: UITextView?

    init(textView: UITextView?) {
        self.textView = textView
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ rect: CGRect) {
        guard let textView else { return }
        let lm = textView.layoutManager
        let text = textView.text ?? ""
        guard !text.isEmpty else { return }

        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        context?.fill(rect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: AutomatorEditorContainer.lineNumberFont,
            .foregroundColor: UIColor(white: 0.4, alpha: 1)
        ]

        let nsText = text as NSString
        let contentOffset = textView.contentOffset.y
        let visibleTop = contentOffset
        let visibleBottom = contentOffset + textView.bounds.height
        let insetTop = textView.textContainerInset.top

        var lineNumber = 1
        var charIndex = 0

        while charIndex <= nsText.length {
            let glyphRange: NSRange
            if charIndex < nsText.length {
                glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            } else {
                // Last line after final newline
                glyphRange = NSRange(location: lm.numberOfGlyphs, length: 0)
            }

            var lineRect: CGRect
            if glyphRange.location < lm.numberOfGlyphs {
                lineRect = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            } else if lm.numberOfGlyphs > 0 {
                lineRect = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil)
                lineRect.origin.y += lineRect.height
            } else {
                lineRect = CGRect(x: 0, y: 0, width: bounds.width, height: 18)
            }

            let y = lineRect.origin.y + insetTop - contentOffset
            if y > visibleBottom { break }

            if y + lineRect.height >= visibleTop - contentOffset {
                let numStr = "\(lineNumber)" as NSString
                let size = numStr.size(withAttributes: attrs)
                numStr.draw(
                    at: CGPoint(x: AutomatorEditorContainer.gutterWidth - size.width - 6, y: y + (lineRect.height - size.height) / 2),
                    withAttributes: attrs
                )
            }

            // Find next line
            let nextNewline = nsText.range(of: "\n", options: [], range: NSRange(location: charIndex, length: nsText.length - charIndex))
            if nextNewline.location == NSNotFound {
                break
            }
            charIndex = nextNewline.location + 1
            lineNumber += 1
        }
    }
}
