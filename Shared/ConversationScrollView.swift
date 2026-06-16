//
//  ConversationScrollView.swift
//  FluxHaus
//

import SwiftUI

/// Scrollable message list for a single conversation.
///
/// Uses `ScrollPosition` instead of `ScrollViewReader` so that scroll-to-bottom
/// goes through SwiftUI's state machine rather than calling
/// `NSScrollView.scrollToVisible` directly. The direct AppKit call triggers
/// `layoutSubtreeIfNeeded` inside an existing layout pass, causing the
/// `_NSDetectedLayoutRecursion` hang.
struct ConversationScrollView: View {
    let convId: String
    @Bindable var chat: Chat
    private let scrollDebounceMilliseconds: UInt64 = 50

    @State private var scrollPosition = ScrollPosition()
    @State private var pendingScrollTask: Task<Void, Never>?

    private var convMessages: [ChatMessage] {
        chat.messages(for: convId)
    }

    var body: some View {
        let msgs = convMessages
        let isLoading = chat.isConversationBusy(convId)
        return Group {
            if ChatTranscriptRenderer.usesWebTranscript && ChatTranscriptRenderer.isAvailable {
                ConversationWebView(convId: convId, chat: chat)
            } else {
                nativeTranscript(messages: msgs, isLoading: isLoading)
            }
        }
    }

    private func nativeTranscript(messages msgs: [ChatMessage], isLoading: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(msgs) { message in
                    ChatBubble(
                        message: message,
                        isLastProgress: message.isProgress
                            && message.id == msgs.last(where: \.isProgress)?.id,
                        isPlaying: chat.playingMessageId == message.id,
                        onPlayTapped: {
                            if chat.playingMessageId == message.id {
                                chat.stopPlayback()
                            } else {
                                chat.playAudio(for: message)
                            }
                        }
                    )
                    .id(message.id)
                }
                if isLoading {
                    TypingIndicator()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollPosition($scrollPosition)
        .task(id: convId) {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
            // Pre-warm the markdown cache so MarkdownContentView finds hits immediately.
            warmMarkdownCache(for: msgs.map(\.content))
            scrollPosition = ScrollPosition()
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled else { return }
            scrollPosition.scrollTo(edge: .bottom)
        }
        .onChange(of: msgs.last?.id) {
            Task { @MainActor in scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: msgs.last?.content) {
            pendingScrollTask?.cancel()
            let scheduledConversationId = convId
            pendingScrollTask = Task { @MainActor in
                // `scrollDebounceMilliseconds` keeps streamed-text scrolling
                // smooth without issuing a scroll for every token mutation.
                try? await Task.sleep(for: .milliseconds(scrollDebounceMilliseconds))
                guard !Task.isCancelled, scheduledConversationId == convId else { return }
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: isLoading) {
            if isLoading {
                Task { @MainActor in scrollPosition.scrollTo(edge: .bottom) }
            }
        }
        .onDisappear {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
}
