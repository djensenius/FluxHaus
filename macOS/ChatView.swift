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
        NavigationSplitView {
            chatSidebar
        } detail: {
            chatDetail
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

    private var chatSidebar: some View {
        List {
            ForEach(chat.conversations) { conv in
                Button(action: {
                    Task { await chat.loadConversation(conv) }
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
                .buttonStyle(.plain)
                .listRowBackground(
                    conv.id == chat.conversationId
                        ? Theme.Colors.accent.opacity(0.15) : nil
                )
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let conv = chat.conversations[index]
                    Task { await chat.deleteConversation(conv) }
                }
            }
        }
        .navigationTitle("Conversations")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task { await chat.createNewConversation() }
                }, label: {
                    Image(systemName: "plus")
                })
                .keyboardShortcut("n", modifiers: .command)
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

    private var chatDetail: some View {
        VStack(spacing: 0) {
            if let error = chat.sessionError {
                sessionErrorBanner(error)
            }
            chatMessages
            Divider()
            inputBar
        }
        .background(Theme.Colors.background)
    }

    private func sessionErrorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.Colors.warning)
            Text(error)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Button(action: { chat.sessionError = nil }, label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
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
                            .font(.title)
                            .foregroundColor(Theme.Colors.accent)
                    })
                    .buttonStyle(.plain)
                    .disabled(chat.isLoading)

                    TextField("Ask anything…", text: $inputText, axis: .vertical)
                        .font(Theme.Fonts.bodyMedium)
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
                                ? Theme.Colors.textSecondary
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
                .padding()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chat.isRecording)
    }

    private var recordingOverlay: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .scaleEffect(1.0 + CGFloat(chat.audioLevel) * 0.5)
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .scaleEffect(1.0 + CGFloat(chat.audioLevel) * 0.3)
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(Theme.Colors.accent)
            }
            .animation(.easeOut(duration: 0.08), value: chat.audioLevel)
            .onTapGesture {
                Task { await chat.stopRecordingAndSend() }
            }
            Text("Listening…")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Button(action: {
                Task { await chat.stopRecordingAndSend() }
            }, label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title)
                    .foregroundColor(Theme.Colors.error)
            })
            .buttonStyle(.plain)
        }
        .padding()
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
            if message.role == .user { Spacer() }
            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: 4
            ) {
                Text(message.content)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(foregroundColor)
                    .textSelection(.enabled)
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
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(backgroundColor)
            .cornerRadius(16)
            if message.role != .user { Spacer() }
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
        case .user: return Theme.Colors.background
        case .assistant: return Theme.Colors.textPrimary
        case .error: return Theme.Colors.error
        }
    }

    private var playButtonColor: Color {
        message.role == .user
            ? Theme.Colors.background.opacity(0.8)
            : Theme.Colors.accent
    }
}

#if DEBUG
#Preview {
    ChatView(chat: Chat())
}
#endif
