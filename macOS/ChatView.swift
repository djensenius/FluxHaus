//
//  ChatView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct ChatView: View {
    @Bindable var chat: Chat
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HSplitView {
            chatSidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            chatDetail
                .frame(minWidth: 400)
        }
        .task {
            if chat.conversations.isEmpty {
                await chat.loadConversations()
            }
            if chat.conversationId == nil {
                if chat.conversations.isEmpty {
                    await chat.createNewConversation()
                } else if let first = chat.conversations.first {
                    await chat.loadConversation(first)
                }
            }
        }
    }

    private var chatSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task { await chat.createNewConversation() }
                }, label: {
                    Image(systemName: "plus")
                })
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(12)

            Divider()

            if chat.conversations.isEmpty {
                Spacer()
                Text("No conversations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(selection: Binding(
                    get: { chat.conversationId },
                    set: { newId in
                        if let newId,
                           let conv = chat.conversations.first(
                            where: { $0.id == newId }
                           ) {
                            Task { await chat.loadConversation(conv) }
                        }
                    }
                )) {
                    ForEach(chat.conversations) { conv in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title ?? "Untitled")
                                .font(.body)
                                .lineLimit(1)
                            Text("\(conv.messageCount) messages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(conv.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let conv = chat.conversations[index]
                            Task { await chat.deleteConversation(conv) }
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    private var chatDetail: some View {
        VStack(spacing: 0) {
            if let error = chat.sessionError {
                sessionErrorBanner(error)
            }
            chatMessages
            Divider()
            inputBar
        }
    }

    private func sessionErrorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.Colors.warning)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { chat.sessionError = nil }, label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Theme.Colors.warning.opacity(0.1))
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
                                .controlSize(.small)
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
        Group {
            if chat.isRecording {
                recordingOverlay
            } else {
                HStack(spacing: 8) {
                    Button(action: {
                        chat.startRecording()
                    }, label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.title2)
                            .foregroundColor(Theme.Colors.accent)
                    })
                    .buttonStyle(.plain)
                    .disabled(chat.isLoading)

                    TextField("Ask anything…", text: $inputText, axis: .vertical)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                        .onAppear { isInputFocused = true }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(
                                inputText.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                                ? Color.secondary
                                : Theme.Colors.accent
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        inputText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || chat.isLoading
                    )
                }
                .padding(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chat.isRecording)
    }

    private var recordingOverlay: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .scaleEffect(1.0 + CGFloat(chat.audioLevel) * 0.5)
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .scaleEffect(1.0 + CGFloat(chat.audioLevel) * 0.3)
                Image(systemName: "mic.fill")
                    .font(.body)
                    .foregroundColor(Theme.Colors.accent)
            }
            .animation(.easeOut(duration: 0.08), value: chat.audioLevel)
            .onTapGesture {
                Task { await chat.stopRecordingAndSend() }
            }
            Text("Listening…")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: {
                Task { await chat.stopRecordingAndSend() }
            }, label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundColor(Theme.Colors.error)
            })
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task { await chat.send(text) }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    let isPlaying: Bool
    let onPlayTapped: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: 4
            ) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(foregroundColor)
                    .textSelection(.enabled)
                if message.isVoice && message.audioData != nil {
                    Button(action: onPlayTapped, label: {
                        HStack(spacing: 4) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.caption)
                            Text(isPlaying ? "Stop" : "Play")
                                .font(.caption)
                        }
                        .foregroundColor(playButtonColor)
                    })
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(backgroundColor)
            .cornerRadius(12)
            if message.role != .user { Spacer(minLength: 60) }
        }
        .padding(.horizontal)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return Theme.Colors.accent
        case .assistant: return Theme.Colors.secondaryBackground
        case .error: return Theme.Colors.error.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user: return .white
        case .assistant: return Theme.Colors.textPrimary
        case .error: return Theme.Colors.error
        }
    }

    private var playButtonColor: Color {
        message.role == .user
            ? Color.white.opacity(0.8)
            : Theme.Colors.accent
    }
}

#if DEBUG
#Preview {
    ChatView(chat: Chat())
}
#endif
