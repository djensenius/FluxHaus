//
//  ChatView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var chat: Chat
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var holdRecordStart: Date?
    @State private var pendingImages: [ChatImage] = []
    @State private var showFilePicker = false

    var body: some View {
        HStack(spacing: 0) {
            chatSidebar
                .frame(width: 260)
            Divider()
            chatDetail
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
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("newConversation"))
        ) { _ in
            Task { await chat.createNewConversation() }
        }
    }

    // MARK: - Sidebar

    private var chatSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task { await chat.createNewConversation() }
                }, label: {
                    Image(systemName: "square.and.pencil")
                })
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if chat.conversations.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a new conversation")
                )
            } else {
                List(selection: Binding(
                    get: { chat.conversationId },
                    set: { newId in
                        if let newId,
                           let conv = chat.conversations.first(where: { $0.id == newId }) {
                            Task { await chat.loadConversation(conv) }
                        }
                    }
                )) {
                    ForEach(chat.conversations) { conv in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conv.title ?? "Untitled")
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatRelativeDate(conv.updatedAt))
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Text("\(conv.messageCount) messages")
                                .font(.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .tag(conv.id)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await chat.deleteConversation(conv) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let conv = chat.conversations[index]
                            Task { await chat.deleteConversation(conv) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func formatRelativeDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString)
                ?? ISO8601DateFormatter().date(from: isoString) else {
            return ""
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MMM d"
            return dayFormatter.string(from: date)
        }
    }

    // MARK: - Chat detail

    private var chatDetail: some View {
        VStack(spacing: 0) {
            if let error = chat.sessionError {
                sessionErrorBanner(error)
            }
            chatMessages
            if chat.messages.isEmpty || chat.messages.last?.role == .assistant {
                SuggestionChipsView { command in
                    inputText = command
                    sendMessage()
                }
                .padding(.vertical, 8)
            }
            Divider()
            imagePreviewBar
            inputBar
        }
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
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            })
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Theme.Colors.warning.opacity(0.1))
    }

    // MARK: - Messages

    private var chatMessages: some View {
        ZStack {
            ForEach(chat.cachedConversationIds, id: \.self) { convId in
                conversationScrollView(for: convId)
                    .opacity(convId == chat.conversationId ? 1 : 0)
                    .allowsHitTesting(convId == chat.conversationId)
            }
        }
    }

    private func conversationScrollView(for convId: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chat.messages(for: convId)) { message in
                        let isLastProgress = message.isProgress
                            && message.id == chat.messages(for: convId)
                                .last(where: \.isProgress)?.id
                        ChatBubble(
                            message: message,
                            isLastProgress: isLastProgress,
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
                    if chat.isLoading && convId == chat.conversationId {
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
                .padding(.vertical, 12)
                Color.clear.frame(height: 1).id("bottom")
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.messages(for: convId).last?.id) {
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: chat.isLoading) {
                if chat.isLoading && convId == chat.conversationId {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Image preview

    @ViewBuilder
    private var imagePreviewBar: some View {
        if !pendingImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingImages) { img in
                        ZStack(alignment: .topTrailing) {
                            if let data = img.uiImageData, let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button(action: {
                                pendingImages.removeAll { $0.id == img.id }
                            }, label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            })
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            Divider()
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        Group {
            if chat.isRecording {
                recordingOverlay
            } else {
                HStack(spacing: 8) {
                    micButton

                    Button(action: { showFilePicker = true }, label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                            .foregroundColor(
                                chat.isLoading ? Theme.Colors.textSecondary : Theme.Colors.accent
                            )
                    })
                    .buttonStyle(.plain)
                    .disabled(chat.isLoading)
                    .fileImporter(
                        isPresented: $showFilePicker,
                        allowedContentTypes: [.image],
                        allowsMultipleSelection: true
                    ) { result in
                        loadFilePickerImages(result)
                    }

                    TextField("Ask anything…", text: $inputText, axis: .vertical)
                        .font(Theme.Fonts.bodyLarge)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                        .onAppear { isInputFocused = true }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(canSend ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
                .padding(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chat.isRecording)
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !pendingImages.isEmpty
        return (hasText || hasImages) && !chat.isLoading
    }

    private var micButton: some View {
        Image(systemName: "mic.circle.fill")
            .font(.title2)
            .foregroundColor(
                chat.isLoading ? Theme.Colors.textSecondary : Theme.Colors.accent
            )
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
                    .font(Theme.Fonts.bodyMedium)
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
                    .font(.title2)
                    .foregroundColor(Theme.Colors.error)
            })
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        let images = pendingImages
        inputText = ""
        pendingImages = []
        Task { await chat.send(text, images: images) }
    }

    private func loadFilePickerImages(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var loaded: [ChatImage] = []
        for url in urls.prefix(4) {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                let mediaType = ext == "png" ? "image/png" : "image/jpeg"
                loaded.append(ChatImage(mediaType: mediaType, base64: data.base64EncodedString()))
            }
        }
        pendingImages.append(contentsOf: loaded)
    }
}

#if DEBUG
#Preview {
    ChatView(chat: Chat())
}
#endif
