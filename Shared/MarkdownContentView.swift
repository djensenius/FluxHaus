//
//  MarkdownContentView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-13.
//

import SwiftUI

// MARK: - Block-level markdown parser

/// Represents a parsed block of markdown content.
enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case codeBlock(language: String?, code: String)
    case image(alt: String, url: String)
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case thematicBreak

    var id: String {
        switch self {
        case .heading(_, let text): return "h-\(text.hashValue)"
        case .paragraph(let text): return "p-\(text.hashValue)"
        case .bulletList(let items): return "ul-\(items.hashValue)"
        case .numberedList(let items): return "ol-\(items.hashValue)"
        case .codeBlock(_, let code): return "code-\(code.hashValue)"
        case .image(_, let url): return "img-\(url.hashValue)"
        case .blockquote(let text): return "bq-\(text.hashValue)"
        case .table(let headers, let rows): return "tbl-\(headers.hashValue)-\(rows.hashValue)"
        case .thematicBreak: return "hr-\(UUID().uuidString)"
        }
    }
}

/// Parses a markdown string into an array of block elements.
// swiftlint:disable:next cyclomatic_complexity
func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = markdown.components(separatedBy: "\n")
    var index = 0

    while index < lines.count {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Empty line — skip
        if trimmed.isEmpty {
            index += 1
            continue
        }

        // Thematic break
        if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0 == " " })
            && trimmed.filter({ $0 != " " }).count >= 3
            && Set(trimmed.filter({ $0 != " " })).count == 1 {
            blocks.append(.thematicBreak)
            index += 1
            continue
        }

        // Heading
        if let match = trimmed.range(of: #"^(#{1,6})\s+(.+)$"#, options: .regularExpression) {
            let full = String(trimmed[match])
            let hashCount = full.prefix(while: { $0 == "#" }).count
            let text = String(full.drop(while: { $0 == "#" }).dropFirst()) // drop space
            blocks.append(.heading(level: hashCount, text: text))
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
                    index += 1
                    break
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

        // Image (standalone line)
        if let imgMatch = trimmed.range(
            of: #"^!\[([^\]]*)\]\(([^)]+)\)$"#,
            options: .regularExpression
        ) {
            let full = String(trimmed[imgMatch])
            let altStart = full.index(full.startIndex, offsetBy: 2)
            let altEnd = full.range(of: "]")!.lowerBound
            let urlStart = full.range(of: "(")!.upperBound
            let urlEnd = full.index(full.endIndex, offsetBy: -1)
            let alt = String(full[altStart..<altEnd])
            let url = String(full[urlStart..<urlEnd])
            blocks.append(.image(alt: alt, url: url))
            index += 1
            continue
        }

        // Blockquote
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            var quoteLines: [String] = []
            while index < lines.count {
                let qLine = lines[index].trimmingCharacters(in: .whitespaces)
                if qLine.hasPrefix("> ") {
                    quoteLines.append(String(qLine.dropFirst(2)))
                } else if qLine == ">" {
                    quoteLines.append("")
                } else if qLine.isEmpty && !quoteLines.isEmpty {
                    break
                } else {
                    break
                }
                index += 1
            }
            blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
            continue
        }

        // Table (pipe-delimited, requires header + separator row)
        if trimmed.hasPrefix("|"), index + 1 < lines.count {
            let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if nextLine.hasPrefix("|") && nextLine.contains("-") {
                let headers = parseTableRow(trimmed)
                var dataRows: [[String]] = []
                index += 2 // skip header + separator
                while index < lines.count {
                    let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard rowLine.hasPrefix("|") else { break }
                    dataRows.append(parseTableRow(rowLine))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: dataRows))
                continue
            }
        }

        // Bullet list
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            var items: [String] = []
            while index < lines.count {
                let lLine = lines[index].trimmingCharacters(in: .whitespaces)
                if lLine.hasPrefix("- ") || lLine.hasPrefix("* ") || lLine.hasPrefix("• ") {
                    items.append(String(lLine.dropFirst(2)))
                } else if lLine.isEmpty {
                    break
                } else if lLine.hasPrefix("  ") && !items.isEmpty {
                    // Continuation of previous item
                    items[items.count - 1] += " " + lLine.trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
                index += 1
            }
            if !items.isEmpty { blocks.append(.bulletList(items: items)) }
            continue
        }

        // Numbered list
        if trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil {
            var items: [String] = []
            while index < lines.count {
                let lLine = lines[index].trimmingCharacters(in: .whitespaces)
                if let range = lLine.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                    items.append(String(lLine[range.upperBound...]))
                } else if lLine.isEmpty {
                    break
                } else if lLine.hasPrefix("  ") && !items.isEmpty {
                    items[items.count - 1] += " " + lLine.trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
                index += 1
            }
            if !items.isEmpty { blocks.append(.numberedList(items: items)) }
            continue
        }

        // Paragraph — collect consecutive non-blank, non-special lines
        var paraLines: [String] = []
        while index < lines.count {
            let pLine = lines[index]
            let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
            if pTrimmed.isEmpty
                || pTrimmed.hasPrefix("#")
                || pTrimmed.hasPrefix("```")
                || pTrimmed.hasPrefix("> ")
                || pTrimmed.hasPrefix("| ")
                || pTrimmed.hasPrefix("|")
                || pTrimmed.hasPrefix("- ")
                || pTrimmed.hasPrefix("* ")
                || pTrimmed.hasPrefix("• ")
                || pTrimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil {
                break
            }
            paraLines.append(pTrimmed)
            index += 1
        }
        if !paraLines.isEmpty {
            blocks.append(.paragraph(text: paraLines.joined(separator: " ")))
        }
    }

    return blocks
}

/// Splits a pipe-delimited table row into cell strings.
private func parseTableRow(_ row: String) -> [String] {
    row.split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

// MARK: - Inline markdown rendering

/// Renders inline markdown (bold, italic, code, links) as AttributedString.
private func inlineMarkdown(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

// MARK: - Block views

struct MarkdownContentView: View {
    let content: String
    let role: ChatRole

    private var blocks: [MarkdownBlock] {
        parseMarkdownBlocks(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level: level))
                .fontWeight(.semibold)
                .foregroundColor(textColor)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(bodyFont)
                .foregroundColor(textColor)
                .fixedSize(horizontal: false, vertical: true)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(bodyFont)
                            .foregroundColor(textColor.opacity(0.6))
                        Text(inlineMarkdown(item))
                            .font(bodyFont)
                            .foregroundColor(textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(bodyFont)
                            .foregroundColor(textColor.opacity(0.6))
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(inlineMarkdown(item))
                            .font(bodyFont)
                            .foregroundColor(textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, language != nil ? 4 : 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .image(let alt, let url):
            if let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                            .font(.callout)
                            .foregroundColor(Theme.Colors.textSecondary)
                    case .empty:
                        ProgressView()
                            .frame(height: 100)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

        case .blockquote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.Colors.accent.opacity(0.5))
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(bodyFont)
                    .foregroundColor(textColor.opacity(0.85))
                    .italic()
                    .padding(.leading, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Table view

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columnCount = headers.count
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount)

        return LazyVGrid(columns: columns, spacing: 0) {
            // Header row
            ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                Text(inlineMarkdown(header))
                    .font(bodyFont)
                    .fontWeight(.semibold)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(codeBackground.opacity(0.6))
            }

            // Separator
            ForEach(0..<columnCount, id: \.self) { _ in
                Divider()
            }

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                ForEach(0..<columnCount, id: \.self) { colIdx in
                    let cell = colIdx < row.count ? row[colIdx] : ""
                    Text(inlineMarkdown(cell))
                        .font(bodyFont)
                        .foregroundColor(textColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(rowIdx % 2 == 0 ? Color.clear : codeBackground.opacity(0.3))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(textColor.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Styling helpers

    private var textColor: Color {
        switch role {
        case .user: return Theme.Colors.background
        case .assistant: return Theme.Colors.textPrimary
        case .error: return Theme.Colors.error
        }
    }

    private var bodyFont: Font {
        Theme.Fonts.bodyLarge
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 22, weight: .bold, design: .default)
        case 2: return .system(size: 20, weight: .bold, design: .default)
        case 3: return .system(size: 18, weight: .semibold, design: .default)
        default: return .system(size: 17, weight: .semibold, design: .default)
        }
    }

    private var codeBackground: Color {
        role == .user
            ? Color.white.opacity(0.15)
            : Theme.Colors.secondaryBackground
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            MarkdownContentView(
                content: """
                # Welcome
                Here is a **bold** statement and some `inline code`.

                ## Features
                - First item with *emphasis*
                - Second item
                - Third item

                1. Step one
                2. Step two
                3. Step three

                ```swift
                let greeting = "Hello, World!"
                print(greeting)
                ```

                > This is a blockquote with some wisdom.

                | Feature | Status | Notes |
                | --- | --- | --- |
                | Tables | ✅ Done | With alternating rows |
                | Code blocks | ✅ Done | Syntax label support |
                | Images | ✅ Done | AsyncImage loading |

                ---

                ![Example image](https://picsum.photos/400/200)

                And a final paragraph.
                """,
                role: .assistant
            )
            .padding()
        }
    }
    .background(Theme.Colors.background)
}
#endif
