//
//  MarkdownLoader.swift
//  AntiMatter
//
//  Loads markdown files bundled under `Resources/HelpContent/` and parses them
//  into block-level units (headings, paragraphs, bullet lists) for SwiftUI
//  rendering. Inline bold/italic come from SwiftUI's built-in
//  `AttributedString(markdown:)` parser.
//
//  Supports a line-prefix conditional reveal token used by progression-aware
//  sections like Common Abbreviations:
//
//      - [if:infinity] **IP**: Infinity Point
//      - [if:eternity] **EP**: Eternity Point
//
//  When the flag isn't in `activeFlags`, the line is stripped before any
//  block parsing.
//

import Foundation

struct HelpBlock: Identifiable {
    enum Kind {
        case heading
        case paragraph
        case bullet
    }

    let id = UUID()
    let kind: Kind
    let content: AttributedString
}

enum MarkdownLoader {
    /// Load and parse a help markdown file from the app bundle.
    /// - Parameters:
    ///   - filename: Stem of the `.md` file (without extension).
    ///   - activeFlags: Set of progression flags that should "reveal" their
    ///     gated lines (e.g. `["infinity", "eternity"]`).
    /// - Returns: An ordered array of blocks ready to render. Empty if the
    ///   file isn't found.
    static func load(filename: String, activeFlags: Set<String> = []) -> [HelpBlock] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "md", subdirectory: "HelpContent")
                ?? Bundle.main.url(forResource: filename, withExtension: "md") else {
            return []
        }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(raw, activeFlags: activeFlags)
    }

    /// Plain-text body extracted from a file, used by the index search filter.
    /// Inline markdown markers + heading/bullet prefixes are stripped; gated
    /// lines are evaluated against `activeFlags`.
    static func plainText(filename: String, activeFlags: Set<String> = []) -> String {
        let blocks = load(filename: filename, activeFlags: activeFlags)
        return blocks.map { String($0.content.characters) }.joined(separator: " ")
    }

    // MARK: - Parser

    static func parse(_ raw: String, activeFlags: Set<String>) -> [HelpBlock] {
        var blocks: [HelpBlock] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            if let attr = attributedString(from: joined) {
                blocks.append(HelpBlock(kind: .paragraph, content: attr))
            }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for rawLine in raw.components(separatedBy: "\n") {
            // Resolve conditional gate; drop the line entirely if the flag is inactive.
            guard let resolved = applyConditional(to: rawLine, activeFlags: activeFlags) else { continue }
            let line = resolved.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line.hasPrefix("## ") {
                flushParagraph()
                let headingText = String(line.dropFirst(3))
                if let attr = attributedString(from: headingText) {
                    blocks.append(HelpBlock(kind: .heading, content: attr))
                }
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                let itemText = String(line.dropFirst(2))
                if let attr = attributedString(from: itemText) {
                    blocks.append(HelpBlock(kind: .bullet, content: attr))
                }
                continue
            }

            paragraphBuffer.append(line)
        }
        flushParagraph()
        return blocks
    }

    /// Returns the line with the conditional prefix removed, or `nil` if the
    /// line is gated and its flag isn't active.
    ///
    /// Supported forms (after leading list marker / whitespace):
    ///   `[if:flag] rest...`     — keep if `flag` is active
    ///   `[unless:flag] rest...` — keep if `flag` is NOT active
    private static func applyConditional(to line: String, activeFlags: Set<String>) -> String? {
        // Find a "[if:...]" or "[unless:...]" token, optionally after a list marker.
        // We match against the line with leading whitespace + list marker preserved
        // so we can splice the rest back together.
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let leadingWhitespace = String(line.prefix(line.count - trimmed.count))

        // Detect list-marker prefix.
        var listMarker = ""
        var rest = String(trimmed)
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") {
            listMarker = String(rest.prefix(2))
            rest = String(rest.dropFirst(2))
        }

        guard rest.hasPrefix("[") else { return line }

        // Look for closing "]"
        guard let closing = rest.firstIndex(of: "]") else { return line }
        let token = String(rest[rest.index(after: rest.startIndex)..<closing])
        let afterClosing = rest.index(after: closing)
        var remainder = String(rest[afterClosing...])
        if remainder.hasPrefix(" ") { remainder.removeFirst() }

        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return line }
        let kind = parts[0]
        let flag = parts[1]

        switch kind {
        case "if":
            return activeFlags.contains(flag) ? leadingWhitespace + listMarker + remainder : nil
        case "unless":
            return activeFlags.contains(flag) ? nil : leadingWhitespace + listMarker + remainder
        default:
            return line
        }
    }

    private static func attributedString(from raw: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false
        return try? AttributedString(markdown: raw, options: options)
    }
}
