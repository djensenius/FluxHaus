//
//  MarkdownParser.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-13.
//

import Foundation

// MARK: - Block-level markdown parser

/// Parses inline markdown (bold, italic, code, links) into an AttributedString.
/// This is called from `parseMarkdownBlocks` on a background thread so that
/// `AttributedString(markdown:)` — which is not free — never runs on the main thread.
func inlineMarkdown(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

/// Represents a parsed block of markdown content.
/// Text fields store pre-computed `AttributedString` values so that
/// `MarkdownContentView.blockView` can render them directly without any
/// additional parsing work on the main thread.
enum MarkdownBlock {
    case heading(level: Int, text: AttributedString)
    case paragraph(text: AttributedString)
    case bulletList(items: [AttributedString])
    case numberedList(items: [AttributedString])
    case codeBlock(language: String?, code: String)
    case image(alt: String, url: String)
    case blockquote(text: AttributedString)
    case table(headers: [AttributedString], rows: [[AttributedString]])
    case thematicBreak
}

// Parses a markdown string into an array of block elements.
// Regex-based checks replaced with character-iteration helpers to avoid per-call
// regex compilation overhead, which caused multi-second main-thread hangs.
// swiftlint:disable:next cyclomatic_complexity function_body_length
func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = markdown.components(separatedBy: "\n")
    var index = 0

    while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { index += 1; continue }

        // Thematic break
        if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0 == " " })
            && trimmed.filter({ $0 != " " }).count >= 3
            && Set(trimmed.filter({ $0 != " " })).count == 1 {
            blocks.append(.thematicBreak)
            index += 1
            continue
        }

        // Heading
        if let (level, text) = parseHeading(trimmed) {
            blocks.append(.heading(level: level, text: inlineMarkdown(text)))
            index += 1
            continue
        }

        // Fenced code block
        if trimmed.hasPrefix("```") {
            let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var codeLines: [String] = []
            index += 1
            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    index += 1; break
                }
                codeLines.append(lines[index])
                index += 1
            }
            blocks.append(.codeBlock(
                language: language.isEmpty ? nil : language,
                code: codeLines.joined(separator: "\n")
            ))
            continue
        }

        if let (alt, url) = parseImage(trimmed) {
            blocks.append(.image(alt: alt, url: url))
            index += 1
            continue
        }

        // Blockquote
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            var quoteLines: [String] = []
            while index < lines.count {
                let qLine = lines[index].trimmingCharacters(in: .whitespaces)
                if qLine.hasPrefix("> ") { quoteLines.append(String(qLine.dropFirst(2)))
                } else if qLine == ">" { quoteLines.append("")
                } else { break }
                index += 1
            }
            blocks.append(.blockquote(text: inlineMarkdown(quoteLines.joined(separator: "\n"))))
            continue
        }

        // Table (pipe-delimited, requires header + separator row)
        if trimmed.contains("|"), index + 1 < lines.count {
            let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if isTableSeparator(nextLine) {
                let headers = parseTableRow(trimmed)
                guard headers.count > 1 else {
                    index += 1
                    blocks.append(.paragraph(text: inlineMarkdown(trimmed)))
                    continue
                }
                var dataRows: [[AttributedString]] = []
                index += 2
                while index < lines.count {
                    let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard rowLine.contains("|"), !rowLine.isEmpty else { break }
                    dataRows.append(parseTableRow(rowLine).map(inlineMarkdown))
                    index += 1
                }
                blocks.append(.table(headers: headers.map(inlineMarkdown), rows: dataRows))
                continue
            }
        }

        // Bullet list
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            var rawItems: [String] = []
            while index < lines.count {
                let lLine = lines[index].trimmingCharacters(in: .whitespaces)
                if lLine.hasPrefix("- ") || lLine.hasPrefix("* ") || lLine.hasPrefix("• ") {
                    rawItems.append(String(lLine.dropFirst(2)))
                } else if lLine.isEmpty {
                    break
                } else if lLine.hasPrefix("  ") && !rawItems.isEmpty {
                    rawItems[rawItems.count - 1] += " " + lLine.trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
                index += 1
            }
            if !rawItems.isEmpty { blocks.append(.bulletList(items: rawItems.map(inlineMarkdown))) }
            continue
        }

        // Numbered list
        if parseNumberedListPrefix(trimmed) != nil {
            var rawItems: [String] = []
            while index < lines.count {
                let lLine = lines[index].trimmingCharacters(in: .whitespaces)
                if let afterPrefix = parseNumberedListPrefix(lLine) {
                    rawItems.append(String(lLine[afterPrefix...]))
                } else if lLine.isEmpty {
                    break
                } else if lLine.hasPrefix("  ") && !rawItems.isEmpty {
                    rawItems[rawItems.count - 1] += " " + lLine.trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
                index += 1
            }
            if !rawItems.isEmpty { blocks.append(.numberedList(items: rawItems.map(inlineMarkdown))) }
            continue
        }

        // Paragraph — collect consecutive non-blank, non-special lines
        var paraLines: [String] = []
        while index < lines.count {
            let pTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if pTrimmed.isEmpty
                || pTrimmed.hasPrefix("#") || pTrimmed.hasPrefix("```")
                || pTrimmed.hasPrefix("> ") || pTrimmed.hasPrefix("|")
                || (pTrimmed.contains("|") && isLikelyTableRow(
                    pTrimmed, nextLine: index + 1 < lines.count ? lines[index + 1] : nil))
                || pTrimmed.hasPrefix("- ") || pTrimmed.hasPrefix("* ")
                || pTrimmed.hasPrefix("• ") || parseNumberedListPrefix(pTrimmed) != nil {
                break
            }
            paraLines.append(pTrimmed)
            index += 1
        }
        if !paraLines.isEmpty {
            blocks.append(.paragraph(text: inlineMarkdown(paraLines.joined(separator: " "))))
        }
    }

    return blocks
}

// MARK: - Parser helpers (all regex-free)

/// Parses an inline image `![alt](url)` without regex.
private func parseImage(_ str: String) -> (alt: String, url: String)? {
    guard str.hasPrefix("![") else { return nil }
    var idx = str.index(str.startIndex, offsetBy: 2)
    let altStart = idx
    while idx < str.endIndex && str[idx] != "]" { idx = str.index(after: idx) }
    guard idx < str.endIndex else { return nil }
    let alt = String(str[altStart..<idx])
    idx = str.index(after: idx)
    guard idx < str.endIndex && str[idx] == "(" else { return nil }
    idx = str.index(after: idx)
    let urlStart = idx
    while idx < str.endIndex && str[idx] != ")" { idx = str.index(after: idx) }
    guard idx < str.endIndex && str.index(after: idx) == str.endIndex else { return nil }
    let url = String(str[urlStart..<idx])
    return url.isEmpty ? nil : (alt: alt, url: url)
}

/// Parses a heading line (e.g. `## Title`) without regex.
private func parseHeading(_ str: String) -> (level: Int, text: String)? {
    guard str.first == "#" else { return nil }
    var level = 0
    var idx = str.startIndex
    while idx < str.endIndex && str[idx] == "#" && level < 6 {
        level += 1; idx = str.index(after: idx)
    }
    guard idx < str.endIndex && (str[idx] == " " || str[idx] == "\t") else { return nil }
    idx = str.index(after: idx)
    let text = String(str[idx...])
    return text.isEmpty ? nil : (level: level, text: text)
}

/// Returns the index past the numbered-list prefix (e.g. `1. ` or `2) `) without regex.
private func parseNumberedListPrefix(_ str: String) -> String.Index? {
    var idx = str.startIndex
    guard idx < str.endIndex && str[idx].isNumber else { return nil }
    while idx < str.endIndex && str[idx].isNumber { idx = str.index(after: idx) }
    guard idx < str.endIndex && (str[idx] == "." || str[idx] == ")") else { return nil }
    idx = str.index(after: idx)
    guard idx < str.endIndex && (str[idx] == " " || str[idx] == "\t") else { return nil }
    return str.index(after: idx)
}

/// Returns true if `line` is a table separator row (e.g. `| --- | :--: |`).
private func isTableSeparator(_ line: String) -> Bool {
    line.contains("|") && line.contains("-")
        && line.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
}

private func isLikelyTableRow(_ line: String, nextLine: String?) -> Bool {
    guard let next = nextLine?.trimmingCharacters(in: .whitespaces) else { return false }
    return isTableSeparator(next)
}

/// Splits a pipe-delimited table row into cell strings.
private func parseTableRow(_ row: String) -> [String] {
    row.split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}
