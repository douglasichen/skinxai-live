import Foundation

/// Claude's text, ready to show word by word: paragraphs, simple lists and **bold** (chat.js `rich`); anything
/// else stays plain text (headings lose their "#", *italic* and `code` lose their marks).
public struct ChatText: Hashable, Sendable {
    public struct Run: Hashable, Sendable {
        public var text: String
        public var bold: Bool
    }

    /// The text in runs of the same style.
    public private(set) var runs: [Run]
    /// Where each word ends, as a count of characters from the start of the text.
    public private(set) var wordEnds: [Int]

    public var plain: String { runs.map(\.text).joined() }
    public var wordCount: Int { wordEnds.count }

    public init(markdown: String) {
        let blocks = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\n[ \t]*\n\s*"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}")
        let text = blocks.map { block in
            block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression) }
                .filter { !$0.isEmpty }
                .map(Self.listLine)
                .joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        runs = Self.inline(text)
        wordEnds = Self.wordEnds(runs.map(\.text).joined())
    }

    /// The first `words` words of the text (all of it when `words` ≥ `wordCount`), as a character count.
    public func visibleLength(words: Int) -> Int {
        guard words > 0, !wordEnds.isEmpty else { return 0 }
        return wordEnds[min(words, wordEnds.count) - 1]
    }

    /// "- item", "* item", "• item" → "• item"; "1) item" → "1. item".
    static func listLine(_ line: String) -> String {
        guard let match = line.range(of: #"^([-*•]|\d+[.)])\s+"#, options: .regularExpression) else { return line }
        let marker = line[match].trimmingCharacters(in: .whitespaces)
        let rest = String(line[match.upperBound...])
        if let number = Int(marker.dropLast()) { return "\(number). \(rest)" }
        return "• \(rest)"
    }

    /// **bold** runs; stray "**", *italic* marks and `code` marks are dropped.
    static func inline(_ text: String) -> [Run] {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: #"\*([^*\s][^*]*?)\*"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)
        }
        var runs: [Run] = []
        func add(_ s: String, bold: Bool) {
            guard !s.isEmpty else { return }
            if let last = runs.last, last.bold == bold { runs[runs.count - 1].text += s } else { runs.append(Run(text: s, bold: bold)) }
        }
        var rest = Substring(text)
        while let open = rest.range(of: "**"), let close = rest[open.upperBound...].range(of: "**"),
              !rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
            add(clean(String(rest[..<open.lowerBound])), bold: false)
            add(clean(String(rest[open.upperBound..<close.lowerBound])), bold: true)
            rest = rest[close.upperBound...]
        }
        add(clean(String(rest)), bold: false)
        return runs
    }

    static func wordEnds(_ text: String) -> [Int] {
        var ends: [Int] = []
        var inWord = false
        var offset = 0
        for ch in text {
            if ch.isWhitespace {
                if inWord { ends.append(offset) }
                inWord = false
            } else {
                inWord = true
            }
            offset += 1
        }
        if inWord { ends.append(offset) }
        return ends
    }
}
