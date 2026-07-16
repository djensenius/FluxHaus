//
//  ChatBubble.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-13.
//

// swiftlint:disable file_length

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Bubble shape

private let bubbleRadius: CGFloat = 18

// MARK: - Image thumbnail grid

struct ChatImageGrid: View {
    let images: [ChatImage]
    let maxHeight: CGFloat

    var body: some View {
        if images.count == 1, let img = images.first, let data = img.uiImageData {
            imageView(from: data)
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(images) { img in
                    if let data = img.uiImageData {
                        imageView(from: data)
                            .frame(height: maxHeight / 2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func imageView(from data: Data) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        #endif
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    let message: ChatMessage
    let isLastProgress: Bool
    let isPlaying: Bool
    let onPlayTapped: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Image attachments
                if !message.images.isEmpty {
                    ChatImageGrid(images: message.images, maxHeight: 220)
                }

                // Message content
                if message.isProgress {
                    progressContent
                } else if message.role == .assistant {
                    MarkdownContentView(content: message.content, role: .assistant)
                        .textSelection(.enabled)
                } else if message.role == .error {
                    Text(message.content)
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundColor(Theme.Colors.error)
                        .textSelection(.enabled)
                } else {
                    Text(markdownAttributed(message.content))
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundColor(Theme.Colors.background)
                        .textSelection(.enabled)
                }

                // Voice playback button
                if message.isVoice && message.audioData != nil {
                    playButton
                }
            }
            .padding(.horizontal, message.isProgress ? 8 : 14)
            .padding(.vertical, message.isProgress ? 6 : 12)
            .background(bubbleBackground)

            if message.role != .user { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Sub-views

    private var progressContent: some View {
        HStack(spacing: 8) {
            if isLastProgress {
                #if os(macOS)
                SwiftUISpinner()
                #else
                ProgressView().controlSize(.small)
                #endif
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Text(message.content)
                .font(Theme.Fonts.bodySmall).italic()
                .foregroundColor(Theme.Colors.textSecondary)
                .textSelection(.enabled)
        }
    }

    private var playButton: some View {
        Button(action: onPlayTapped) {
            HStack(spacing: 4) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(Theme.Fonts.caption)
                Text(isPlaying ? "Stop" : "Play")
                    .font(Theme.Fonts.caption)
            }
            .foregroundColor(playButtonColor)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isProgress {
            Color.clear
        } else {
            switch message.role {
            case .user:
                RoundedRectangle(cornerRadius: bubbleRadius)
                    .fill(Theme.Colors.accent)
            case .assistant:
                #if os(visionOS)
                RoundedRectangle(cornerRadius: bubbleRadius)
                    .fill(.ultraThinMaterial)
                #else
                RoundedRectangle(cornerRadius: bubbleRadius)
                    .fill(Theme.Colors.secondaryBackground)
                #endif
            case .error:
                RoundedRectangle(cornerRadius: bubbleRadius)
                    .fill(Theme.Colors.error.opacity(0.15))
            }
        }
    }

    private var playButtonColor: Color {
        message.role == .user
            ? Theme.Colors.background.opacity(0.8)
            : Theme.Colors.accent
    }
}

// MARK: - Conversation tab bar (shared)

/// Horizontal strip of open conversation tabs used on iOS and VisionOS. Shows each
/// open conversation, a transient "New Chat" tab when the active conversation is
/// unsaved, and a button to open a new tab.
struct ConversationTabBar: View {
    @Bindable var chat: Chat

    var body: some View {
        let tabs = chat.openTabConversations
        let showNewTab = chat.conversationId == nil
        if !tabs.isEmpty || showNewTab {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { conv in
                            tabChip(
                                title: conv.title ?? "Untitled",
                                isActive: conv.id == chat.conversationId,
                                onSelect: { Task { await chat.selectTab(conv.id) } },
                                onClose: { Task { await chat.closeTab(conv.id) } }
                            )
                        }
                        if showNewTab {
                            tabChip(title: "New Chat", isActive: true, onSelect: {}, onClose: nil)
                        }
                        Button(action: { chat.startNewConversation() }, label: {
                            Image(systemName: "plus")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        })
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                Divider()
            }
        }
    }

    private func tabChip(
        title: String,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onClose: (() -> Void)?
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Theme.Fonts.caption.weight(isActive ? .semibold : .regular))
                .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
            if let onClose {
                Button(action: onClose, label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.Colors.textSecondary)
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 180)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Theme.Colors.accent.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActive ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.textSecondary.opacity(0.2),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Pasted text attachment chip

/// Compact composer chip representing a large pasted-text attachment.
struct PastedTextChip: View {
    let attachment: PastedTextAttachment
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pasted text")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(attachment.lineCount) lines · \(attachment.charCount) chars")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Full-content viewer for a pasted-text attachment, shown in a sheet.
struct PastedTextDetailView: View {
    let attachment: PastedTextAttachment
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(attachment.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Pasted Text")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

// MARK: - Paste-intercepting composer text field

/// A multiline composer text field that intercepts large clipboard pastes before
/// they enter the editor (mirroring ChatGPT/Claude) and forwards them as
/// `PastedTextAttachment`s instead. Small pastes and normal typing behave as usual.
struct ChatComposerTextField: View {
    @Binding var text: String
    var placeholder: String = "Ask anything…"
    var focusOnAppear: Bool = false
    var onSubmit: () -> Void
    var onPasteLargeText: (String) -> Void

    @State private var measuredHeight: CGFloat = 0

    #if os(macOS)
    private let minHeight: CGFloat = 22
    private let maxHeight: CGFloat = 200
    #else
    private let minHeight: CGFloat = 30
    private let maxHeight: CGFloat = 240
    #endif

    var body: some View {
        ComposerTextView(
            text: $text,
            measuredHeight: $measuredHeight,
            placeholder: placeholder,
            focusOnAppear: focusOnAppear,
            onSubmit: onSubmit,
            onPasteLargeText: onPasteLargeText
        )
        .frame(height: min(max(measuredHeight, minHeight), maxHeight))
    }
}

#if canImport(UIKit)
final class PasteInterceptingTextView: UITextView {
    var onPasteLargeText: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        if let string = UIPasteboard.general.string, PastedTextAttachment.qualifies(string) {
            onPasteLargeText?(string)
            return
        }
        super.paste(sender)
    }
}

struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var placeholder: String
    var focusOnAppear: Bool
    var onSubmit: () -> Void
    var onPasteLargeText: (String) -> Void

    func makeUIView(context: Context) -> PasteInterceptingTextView {
        let view = PasteInterceptingTextView()
        view.delegate = context.coordinator
        view.font = UIFont.systemFont(ofSize: 18)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.textColor = UIColor(Theme.Colors.textPrimary)
        view.onPasteLargeText = onPasteLargeText
        view.text = text

        let label = UILabel()
        label.text = placeholder
        label.font = view.font
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 6)
        ])
        context.coordinator.placeholderLabel = label
        label.isHidden = !text.isEmpty

        if focusOnAppear {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ uiView: PasteInterceptingTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        }
        uiView.onPasteLargeText = onPasteLargeText
        let height = uiView.contentSize.height
        if abs(height - measuredHeight) > 0.5 {
            DispatchQueue.main.async { measuredHeight = height }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        weak var placeholderLabel: UILabel?
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
            parent.measuredHeight = textView.contentSize.height
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }
    }
}
#elseif canImport(AppKit)
final class PasteInterceptingTextView: NSTextView {
    var onPasteLargeText: ((String) -> Void)?
    var placeholderString: String?

    override func paste(_ sender: Any?) {
        if let string = NSPasteboard.general.string(forType: .string),
           PastedTextAttachment.qualifies(string) {
            onPasteLargeText?(string)
            return
        }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholderString, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont.systemFont(ofSize: 15)
        ]
        placeholderString.draw(
            at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
            withAttributes: attrs
        )
    }
}

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var placeholder: String
    var focusOnAppear: Bool
    var onSubmit: () -> Void
    var onPasteLargeText: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder

        let textView = PasteInterceptingTextView()
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.drawsBackground = false
        textView.textColor = NSColor(Theme.Colors.textPrimary)
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.onPasteLargeText = onPasteLargeText
        textView.placeholderString = placeholder
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PasteInterceptingTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.onPasteLargeText = onPasteLargeText
        context.coordinator.recalcHeight()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
            Task { @MainActor in recalcHeight() }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }

        @MainActor
        func recalcHeight() {
            guard let textView, let container = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let height = used + textView.textContainerInset.height * 2
            let binding = parent.$measuredHeight
            if abs(height - binding.wrappedValue) > 0.5 {
                DispatchQueue.main.async { binding.wrappedValue = height }
            }
        }
    }
}
#endif

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ChatBubble(
                message: ChatMessage(role: .user, content: "What's the weather like?"),
                isLastProgress: false,
                isPlaying: false,
                onPlayTapped: {}
            )
            ChatBubble(
                message: ChatMessage(
                    role: .assistant,
                    content: """
                    ## Current Weather\n\nIt's **22°C** and sunny.
                    - UV Index: High\n- Wind: 15 km/h
                    """
                ),
                isLastProgress: false,
                isPlaying: false,
                onPlayTapped: {}
            )
        }
        .padding()
    }
    .background(Theme.Colors.background)
}
#endif
