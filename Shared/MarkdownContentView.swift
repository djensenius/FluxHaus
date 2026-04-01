//
//  MarkdownContentView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-13.
//

import SwiftUI

// MARK: - Blocks cache

/// Global cache for parsed markdown blocks.
/// `parseMarkdownBlocks` is intentionally run on a background thread (via
/// `Task.detached`) and results are stored here keyed by `content.hashValue`.
/// O(1) Int key means cache lookups are always fast regardless of content size.
@MainActor
private final class MarkdownBlocksCache {
    static let shared = MarkdownBlocksCache()
    private var storage: [Int: [MarkdownBlock]] = [:]
    private let maxEntries = 500

    /// Returns cached blocks if available (O(1), no parsing).
    func cached(for key: Int) -> [MarkdownBlock]? { storage[key] }

    /// Stores parsed blocks for a given key.
    func store(_ blocks: [MarkdownBlock], for key: Int) {
        if storage.count >= maxEntries { storage.removeAll() }
        storage[key] = blocks
    }
}

/// Pre-warms the markdown blocks cache for a list of content strings.
/// Call this when loading a conversation so that `MarkdownContentView` finds
/// cache hits immediately, avoiding any main-thread parse on first render.
func warmMarkdownCache(for contents: [String]) {
    Task.detached(priority: .userInitiated) {
        for content in contents {
            let key = content.hashValue
            if await MarkdownBlocksCache.shared.cached(for: key) != nil { continue }
            let result = parseMarkdownBlocks(content)
            await MarkdownBlocksCache.shared.store(result, for: key)
        }
    }
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

    /// Starts empty; populated asynchronously via `.task` so the main thread is
    /// never blocked by `parseMarkdownBlocks`, even for very large AI responses.
    @State private var parsedBlocks: [MarkdownBlock] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parsedBlocks) { block in
                blockView(for: block)
            }
        }
        .task(id: content) {
            let key = content.hashValue
            if let cached = MarkdownBlocksCache.shared.cached(for: key) {
                parsedBlocks = cached
                return
            }
            // Parse on a background thread — never block the main thread.
            let snapshot = content
            let result = await Task.detached(priority: .userInitiated) {
                parseMarkdownBlocks(snapshot)
            }.value
            MarkdownBlocksCache.shared.store(result, for: key)
            parsedBlocks = result
        }
    }

    @ViewBuilder
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(inlineMarkdown(header))
                        .font(bodyFont)
                        .fontWeight(.semibold)
                        .foregroundColor(textColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(codeBackground.opacity(0.6))

            Divider()

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { colIdx in
                        let cell = colIdx < row.count ? row[colIdx] : ""
                        Text(inlineMarkdown(cell))
                            .font(bodyFont)
                            .foregroundColor(textColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(rowIdx % 2 == 0 ? Color.clear : codeBackground.opacity(0.3))
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
        MarkdownContentView(
            content: """
            # Welcome
            Here is a **bold** statement and some `inline code`.

            ## Features
            - First item
            - Second item

            ```swift
            let x = "Hello"
            ```

            > A blockquote.

            | Feature | Status |
            | --- | --- |
            | Tables | ✅ Done |
            | Code | ✅ Done |

            And a final paragraph.
            """,
            role: .assistant
        )
        .padding()
    }
    .background(Theme.Colors.background)
}
#endif
