//
//  ChatView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    let isPlaying: Bool
    let onPlayTapped: () -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(foregroundColor)
                if message.isVoice && message.audioData != nil {
                    Button(action: onPlayTapped, label: {
                        HStack(spacing: 4) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.caption)
                            Text(isPlaying ? "Stop" : "Play")
                                .font(Theme.Fonts.caption)
                        }
                        .foregroundColor(playButtonColor)
                    })
                }
            }
            .padding(12)
            .background(backgroundColor)
            .cornerRadius(16)
            if message.role != .user {
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Theme.Colors.accent
        case .assistant:
            return Theme.Colors.secondaryBackground
        case .error:
            return Theme.Colors.error.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user:
            return Theme.Colors.background
        case .assistant:
            return Theme.Colors.textPrimary
        case .error:
            return Theme.Colors.error
        }
    }

    private var playButtonColor: Color {
        message.role == .user
            ? Theme.Colors.background.opacity(0.8)
            : Theme.Colors.accent
    }
}

struct ChatView: View {
    @Bindable var chat: Chat
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showConversations = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatMessages
                Divider()
                inputBar
            }
            .background(Theme.Colors.background)
            .navigationTitle(chat.conversationId != nil ? "Assistant" : "New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showConversations = true }, label: {
                        Image(systemName: "list.bullet")
                            .foregroundColor(Theme.Colors.accent)
                    })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task { await chat.createNewConversation() }
                        }, label: {
                            Image(systemName: "plus")
                                .foregroundColor(Theme.Colors.accent)
                        })
                        Button(action: { dismiss() }, label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.Colors.textSecondary)
                        })
                    }
                }
            }
            .sheet(isPresented: $showConversations) {
                ConversationListView(chat: chat)
            }
            .task {
                if chat.conversations.isEmpty {
                    await chat.loadConversations()
                }
                if chat.conversationId == nil {
                    await chat.createNewConversation()
                }
            }
        }
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(chat.messages) { message in
                        ChatBubble(
                            message: message,
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
                        HStack {
                            ProgressView()
                                .padding(12)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("loading")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: chat.messages.count) {
                withAnimation {
                    if let last = chat.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chat.isLoading) {
                if chat.isLoading {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: $inputText, axis: .vertical)
                .font(Theme.Fonts.bodyMedium)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button(action: {
                if chat.isRecording {
                    Task { await chat.stopRecordingAndSend() }
                } else {
                    chat.startRecording()
                }
            }, label: {
                Image(systemName: chat.isRecording
                    ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(
                        chat.isRecording
                            ? Theme.Colors.error : Theme.Colors.accent
                    )
            })
            .disabled(chat.isLoading)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(
                        inputText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        ? Theme.Colors.textSecondary
                        : Theme.Colors.accent
                    )
            }
            .disabled(
                inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || chat.isLoading
            )
        }
        .padding()
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task {
            await chat.send(text)
        }
    }
}

struct ConversationListView: View {
    @Bindable var chat: Chat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(chat.conversations) { conv in
                    Button(action: {
                        Task {
                            await chat.loadConversation(conv)
                            dismiss()
                        }
                    }, label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conv.title ?? "Untitled")
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Text("\(conv.messageCount) messages")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    })
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let conv = chat.conversations[index]
                        Task { await chat.deleteConversation(conv) }
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if chat.conversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a new conversation")
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ChatView(chat: Chat())
}
#endif
