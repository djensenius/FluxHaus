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

    @State private var scrollPosition = ScrollPosition()

    private var convMessages: [ChatMessage] {
        chat.messages(for: convId)
    }

    var body: some View {
        let msgs = convMessages
        return ScrollView {
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
                if chat.isLoading {
                    TypingIndicator()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollPosition($scrollPosition)
        .task(id: convId) {
            scrollPosition = ScrollPosition()
            try? await Task.sleep(for: .milliseconds(32))
            scrollPosition.scrollTo(edge: .bottom)
        }
        .onChange(of: msgs.last?.id) {
            Task { @MainActor in scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: chat.isLoading) {
            if chat.isLoading {
                Task { @MainActor in scrollPosition.scrollTo(edge: .bottom) }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
}
