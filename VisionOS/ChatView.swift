//
//  ChatView.swift
//  VisionOS
//
//  Created by David Jensenius on 2026-03-01.
//

import SwiftUI
import PhotosUI

struct ChatView: View {
    @Bindable var chat: Chat
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showConversations = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingImages: [ChatImage] = []
    @State private var showSuggestions = false

    private func updateShowSuggestions() {
        guard let convId = chat.conversationId else { showSuggestions = false; return }
        if chat.isLoading { showSuggestions = false; return }
        let lastReal = chat.messages(for: convId).last(where: { !$0.isProgress })
        showSuggestions = lastReal == nil || lastReal?.role == .assistant
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = chat.sessionError {
                    sessionErrorBanner(error)
                }
                chatMessages
                if showSuggestions {
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
            .scrollContentBackground(.hidden)
            .navigationTitle(
                chat.conversationId != nil ? "Assistant" : "New Chat"
            )
            .navigationBarTitleDisplayMode(.inline)
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
            .onChange(of: chat.isLoading) { updateShowSuggestions() }
            .onChange(of: chat.conversationId) { updateShowSuggestions() }
        }
        .onChange(of: selectedPhotos) {
            Task { await loadSelectedPhotos() }
        }
    }

    // MARK: - Messages

    private var chatMessages: some View {
        Group {
            if let convId = chat.conversationId {
                ConversationScrollView(convId: convId, chat: chat)
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
                            if let data = img.uiImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Button(action: {
                                pendingImages.removeAll { $0.id == img.id }
                            }, label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            })
                            .offset(x: 4, y: -4)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
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
                HStack(spacing: 10) {
                    Button(action: {
                        chat.startRecording()
                    }, label: {
                        Image(systemName: "mic.circle.fill")
                            .font(Theme.Fonts.headerXL())
                            .foregroundColor(Theme.Colors.accent)
                    })
                    .disabled(chat.isLoading)

                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 4,
                        matching: .images
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(
                                chat.isLoading ? Theme.Colors.textSecondary : Theme.Colors.accent
                            )
                    }
                    .disabled(chat.isLoading)

                    TextField("Ask anything…", text: $inputText, axis: .vertical)
                        .font(Theme.Fonts.bodyLarge)
                        .textFieldStyle(.plain)
                        .lineLimit(1...10)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                        .onAppear { isInputFocused = true }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                    .disabled(!canSend)
                }
                .padding()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chat.isRecording)
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !pendingImages.isEmpty
        return (hasText || hasImages) && !chat.isLoading
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
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.accent)
            }
            .animation(.easeOut(duration: 0.08), value: chat.audioLevel)
            .onTapGesture {
                Task { await chat.stopRecordingAndSend() }
            }

            Text("Listening…")
                .font(Theme.Fonts.bodyLarge)
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            audioLevelBars

            Spacer()

            Button(action: {
                Task { await chat.stopRecordingAndSend() }
            }, label: {
                Image(systemName: "stop.circle.fill")
                    .font(Theme.Fonts.headerXL())
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
                    .animation(.easeOut(duration: 0.08), value: chat.audioLevel)
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

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        let images = pendingImages
        inputText = ""
        pendingImages = []
        selectedPhotos = []
        Task { await chat.send(text, images: images) }
    }

    private func loadSelectedPhotos() async {
        var loaded: [ChatImage] = []
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mediaType = "image/jpeg"
                let base64 = data.base64EncodedString()
                loaded.append(ChatImage(mediaType: mediaType, base64: base64))
            }
        }
        pendingImages = loaded
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
        }
        .padding(8)
        .background(Theme.Colors.warning.opacity(0.1))
    }
}

// MARK: - Conversation list

struct ConversationListView: View {
    @Bindable var chat: Chat
    @Environment(\.dismiss) private var dismiss
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var searchText = ""

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty { return chat.conversations }
        return chat.conversations.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredConversations) { conv in
                    Button(action: {
                        Task {
                            await chat.loadConversation(conv)
                            dismiss()
                        }
                    }, label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conv.title ?? "Untitled")
                                    .lineLimit(1)
                                Spacer()
                                Text(formatRelativeDate(conv.updatedAt))
                                    .font(Theme.Fonts.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Text("\(conv.messageCount) messages")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    })
                    .contextMenu {
                        Button(action: {
                            renameText = conv.title ?? ""
                            renamingConversation = conv
                        }, label: {
                            Label("Rename", systemImage: "pencil")
                        })
                        Button(role: .destructive, action: {
                            Task { await chat.deleteConversation(conv) }
                        }, label: {
                            Label("Delete", systemImage: "trash")
                        })
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let conv = filteredConversations[index]
                        Task { await chat.deleteConversation(conv) }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
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
            .task { await chat.loadConversations() }
            .alert(
                "Rename Conversation",
                isPresented: Binding(
                    get: { renamingConversation != nil },
                    set: { if !$0 { renamingConversation = nil } }
                )
            ) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel, action: {
                    renamingConversation = nil
                })
                Button("Save", action: {
                    if let conv = renamingConversation {
                        Task {
                            await chat.renameConversation(conv, to: renameText)
                        }
                    }
                    renamingConversation = nil
                })
            }
        }
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
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "h:mm a"
            return timeFmt.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "MMM d"
            return dayFmt.string(from: date)
        }
    }
}

#if DEBUG
#Preview(windowStyle: .automatic) {
    ChatView(chat: Chat())
}
#endif
