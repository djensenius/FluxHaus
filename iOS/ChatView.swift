//
//  ChatView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-01.
//

import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    let isLastProgress: Bool
    let isPlaying: Bool
    let onPlayTapped: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.isProgress {
                    HStack(spacing: 6) {
                        if isLastProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        Text(message.content)
                            .font(Theme.Fonts.caption).italic()
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                } else if message.role == .assistant {
                    Text(markdownAttributed(message.content))
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(foregroundColor)
                } else {
                    Text(message.content)
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(foregroundColor)
                }
                if message.isVoice && message.audioData != nil {
                    Button(action: onPlayTapped, label: {
                        HStack(spacing: 4) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill").font(.caption)
                            Text(isPlaying ? "Stop" : "Play").font(Theme.Fonts.caption)
                        }
                        .foregroundColor(playButtonColor)
                    })
                }
            }
            .padding(message.isProgress ? 8 : 12)
            .background(message.isProgress ? Color.clear : backgroundColor)
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
        message.role == .user ? Theme.Colors.background.opacity(0.8) : Theme.Colors.accent
    }
}

struct ChatView: View {
    @Bindable var chat: Chat
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showConversations = false
    @State private var holdRecordStart: Date?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                compactLayout
            }
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
        .task { await chat.syncConversationsPeriodically() }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            chatDetail
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            chatDetail
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showConversations = true }, label: {
                            Image(systemName: "list.bullet")
                                .foregroundColor(Theme.Colors.accent)
                        })
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            Task { await chat.createNewConversation() }
                        }, label: {
                            Image(systemName: "plus")
                                .foregroundColor(Theme.Colors.accent)
                        })
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
                .sheet(isPresented: $showConversations) {
                    ConversationListView(chat: chat)
                }
        }
    }

    private var sidebar: some View {
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
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Task { await chat.createNewConversation() }
                }, label: {
                    Image(systemName: "plus")
                        .foregroundColor(Theme.Colors.accent)
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
            if let error = chat.sessionError { sessionErrorBanner(error) }
            chatMessages
            if chat.messages.isEmpty || chat.messages.last?.role == .assistant {
                SuggestionChipsView { inputText = $0; sendMessage() }
                    .padding(.vertical, 8)
            }
            Divider()
            inputBar
        }
        .background(Theme.Colors.background)
        .navigationTitle(chat.conversationId != nil ? "Assistant" : "New Chat")
        .navigationBarTitleDisplayMode(.inline)
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
                            isLastProgress: message.isProgress
                                && message.id == chat.messages.last(where: \.isProgress)?.id,
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
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var inputBar: some View {
        Group {
            if chat.isRecording {
                recordingOverlay
            } else {
                HStack(spacing: 8) {
                    micButton
                    TextField("Ask anything…", text: $inputText, axis: .vertical)
                        .font(Theme.Fonts.bodyMedium)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }

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
        }
        .animation(.easeInOut(duration: 0.2), value: chat.isRecording)
    }

    private var micButton: some View {
        Image(systemName: "mic.circle.fill")
            .font(.title)
            .foregroundColor(chat.isLoading ? Theme.Colors.textSecondary : Theme.Colors.accent)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard holdRecordStart == nil, !chat.isLoading else { return }
                        holdRecordStart = Date()
                        chat.startRecording()
                    }
                    .onEnded { _ in
                        guard let start = holdRecordStart else { return }
                        holdRecordStart = nil
                        if Date().timeIntervalSince(start) > 0.3 {
                            Task { await chat.stopRecordingAndSend() }
                        }
                    }
            )
            .allowsHitTesting(!chat.isLoading)
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
            audioLevelBars
            Spacer()
            Button(action: {
                Task { await chat.stopRecordingAndSend() }
            }, label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title)
                    .foregroundColor(Theme.Colors.error)
            })
        }
        .padding()
    }

    private var audioLevelBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.accent)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        .easeOut(duration: 0.08),
                        value: chat.audioLevel
                    )
            }
        }
        .frame(height: 20)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let thresholds: [Float] = [0.05, 0.2, 0.35, 0.5, 0.65]
        let base: CGFloat = 4
        let maxH: CGFloat = 20
        let level = chat.audioLevel
        if level > thresholds[index] {
            let fraction = CGFloat((level - thresholds[index]) / (1 - thresholds[index]))
            return base + (maxH - base) * min(1, fraction * 1.5)
        }
        return base
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task { await chat.send(text) }
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

#Preview {
    ChatView(chat: Chat())
}
