//
//  ChatView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

// swiftlint:disable file_length
import SwiftUI
import UniformTypeIdentifiers

enum ChatViewStyle {
    case full
    case quick
}

struct ChatView: View {
    @Bindable var chat: Chat
    var style: ChatViewStyle = .full
    private let initialQuickChatExpanded: Bool
    @State private var inputText = ""
    @State private var holdRecordStart: Date?
    @State private var pendingImages: [ChatImage] = []
    @State private var pendingPastedTexts: [PastedTextAttachment] = []
    @State private var previousInputText = ""
    @State private var expandedPastedText: PastedTextAttachment?
    @State private var showFilePicker = false
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var searchText = ""
    // Tracks whether suggestion chips should be visible. Updated only when
    // isLoading or conversationId changes — NOT on every streaming token —
    // so that chatDetail never reads chat.messages during streaming.
    // Reading chat.messages in chatDetail causes the entire ChatView (including
    // the NSTextView-backed multi-line TextField) to re-render on every token,
    // which triggers _NSDetectedLayoutRecursion on macOS.
    @State private var showSuggestions = false
    @State private var quickChatExpanded = false

    init(chat: Chat, style: ChatViewStyle = .full, initialQuickChatExpanded: Bool = false) {
        self.chat = chat
        self.style = style
        self.initialQuickChatExpanded = initialQuickChatExpanded
        _quickChatExpanded = State(initialValue: initialQuickChatExpanded)
    }

    private func updateShowSuggestions() {
        guard let convId = chat.conversationId else { showSuggestions = false; return }
        if chat.isLoading { showSuggestions = false; return }
        let lastReal = chat.messages(for: convId).last(where: { !$0.isProgress })
        let newVal = lastReal == nil || lastReal?.role == .assistant
        showSuggestions = newVal
    }

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty { return chat.conversations }
        return chat.conversations.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Whether the conversation list (sidebar) is currently on screen. Tabs are
    /// redundant while it's visible, so they're only shown when it's hidden.
    private var isConversationListVisible: Bool {
        switch style {
        case .full: return true
        case .quick: return quickChatExpanded
        }
    }

    var body: some View {
        Group {
            switch style {
            case .full:
                HStack(spacing: 0) {
                    chatSidebar
                        .frame(width: 260)
                    Divider()
                    chatDetail
                }
            case .quick:
                quickChatWindow
            }
        }
        .task {
            if chat.conversations.isEmpty {
                await chat.loadConversations()
            }
            if chat.conversationId == nil {
                if let first = chat.conversations.first {
                    await chat.loadConversation(first)
                } else {
                    chat.startNewConversation()
                }
            }
        }
        .task { await chat.syncConversationsPeriodically() }
        .onChange(of: chat.isLoading) { updateShowSuggestions() }
        .onChange(of: chat.conversationId) { updateShowSuggestions() }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("newConversation"))
        ) { _ in
            chat.startNewConversation()
        }
    }

    private var quickChatWindow: some View {
        VStack(spacing: 0) {
            quickChatHeader
            Divider()
            if quickChatExpanded {
                HStack(spacing: 0) {
                    chatSidebar
                        .frame(width: 260)
                    Divider()
                    chatDetail
                }
            } else {
                chatDetail
            }
        }
        .frame(
            minWidth: quickChatExpanded ? 820 : 560,
            idealWidth: quickChatExpanded ? 960 : 720,
            minHeight: 420,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(Theme.Colors.background)
        .animation(.easeInOut(duration: 0.2), value: quickChatExpanded)
    }

    private var quickChatHeader: some View {
        HStack(spacing: 12) {
            Label("Quick Chat", systemImage: "sparkles")
                .font(Theme.Fonts.bodyMedium.weight(.semibold))
            if let activeConversationTitle {
                Text(activeConversationTitle)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: {
                quickChatExpanded.toggle()
            }, label: {
                Label(
                    quickChatExpanded ? "Hide History" : "Show History",
                    systemImage: "sidebar.left"
                )
            })
            .buttonStyle(.borderless)
            Button(action: {
                chat.startNewConversation()
            }, label: {
                Label("New", systemImage: "square.and.pencil")
            })
            .buttonStyle(.borderless)
            Button(action: openAssistantInMainApp, label: {
                Label("Open App", systemImage: "arrow.up.forward.app")
            })
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Colors.secondaryBackground)
    }

    private var activeConversationTitle: String? {
        guard let conversationId = chat.conversationId else { return nil }
        return chat.conversations.first(where: { $0.id == conversationId })?.title
    }

    // MARK: - Sidebar

    private var chatSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {
                    chat.startNewConversation()
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
                    ForEach(filteredConversations) { conv in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conv.title ?? "Untitled")
                                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatRelativeDate(conv.updatedAt))
                                    .font(Theme.Fonts.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Text("\(conv.messageCount) messages")
                                .font(Theme.Fonts.bodySmall)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .tag(conv.id)
                        .listRowSeparator(.visible)
                        .contentShape(Rectangle())
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
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search conversations")
            }
        }
        .background(Theme.Colors.background)
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
                    Task { await chat.renameConversation(conv, to: renameText) }
                }
                renamingConversation = nil
            })
        }
    }

}

extension ChatView {
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

    private var chatDetail: some View {
        VStack(spacing: 0) {
            conversationTabBar
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
            pastedTextBar
            imagePreviewBar
            inputBar
        }
        .onChange(of: inputText) { _, newValue in handleInputChange(newValue) }
        .background(tabCycleShortcuts)
        .sheet(item: $expandedPastedText) { attachment in
            PastedTextDetailView(attachment: attachment) { expandedPastedText = nil }
        }
        .onDrop(of: ["public.image"], isTargeted: nil) { providers in
            loadDroppedImages(providers)
            return true
        }
    }

    // MARK: - Conversation tabs

    @ViewBuilder
    private var conversationTabBar: some View {
        let tabs = chat.openTabConversations
        let showNewTab = chat.conversationId == nil
        if !isConversationListVisible && (!tabs.isEmpty || showNewTab) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs) { conv in
                        conversationTabChip(
                            title: conv.title ?? "Untitled",
                            isActive: conv.id == chat.conversationId,
                            onSelect: { Task { await chat.selectTab(conv.id) } },
                            onClose: { Task { await chat.closeTab(conv.id) } }
                        )
                    }
                    if showNewTab {
                        conversationTabChip(
                            title: "New Chat",
                            isActive: true,
                            onSelect: {},
                            onClose: nil
                        )
                    }
                    Button(action: { chat.startNewConversation() }, label: {
                        Image(systemName: "plus")
                            .font(Theme.Fonts.caption)
                    })
                    .buttonStyle(.borderless)
                    .help("New Chat Tab")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Theme.Colors.secondaryBackground)
            Divider()
        }
    }

    private func conversationTabChip(
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
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.Colors.textSecondary)
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 160)
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

    private var tabCycleShortcuts: some View {
        HStack(spacing: 0) {
            Button(action: { Task { await chat.cycleTab(forward: true) } }, label: { EmptyView() })
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button(action: { Task { await chat.cycleTab(forward: false) } }, label: { EmptyView() })
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
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

    private var chatMessages: some View {
        Group {
            if let convId = chat.conversationId {
                ConversationScrollView(convId: convId, chat: chat)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pastedTextBar: some View {
        if !pendingPastedTexts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingPastedTexts) { attachment in
                        PastedTextChip(
                            attachment: attachment,
                            onTap: { expandedPastedText = attachment },
                            onRemove: {
                                pendingPastedTexts.removeAll { $0.id == attachment.id }
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            Divider()
        }
    }

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

    private var inputBar: some View {
        Group {
            if chat.isRecording {
                recordingOverlay
            } else {
                HStack(spacing: 8) {
                    micButton

                    Button(action: { showFilePicker = true }, label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(Theme.Fonts.headerLarge())
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

                    // Do NOT auto-focus on macOS: activating the NSTextView field
                    // editor while streaming triggers ViewBridge XPC and can
                    // contribute to _NSDetectedLayoutRecursion.
                    ChatComposerTextField(
                        text: $inputText,
                        onSubmit: { sendMessage() },
                        onPasteLargeText: { pending in
                            pendingPastedTexts.append(PastedTextAttachment(text: pending))
                        }
                    )

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
        let hasPasted = !pendingPastedTexts.isEmpty
        return (hasText || hasImages || hasPasted) && !chat.isLoading
    }

    private var micButton: some View {
        Image(systemName: "mic.circle.fill")
            .font(Theme.Fonts.headerLarge())
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
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.error)
            })
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private func sendMessage() {
        let text = inputText
        let images = pendingImages
        let pasted = pendingPastedTexts
        inputText = ""
        previousInputText = ""
        pendingImages = []
        pendingPastedTexts = []
        Task { await chat.send(text, images: images, pastedTexts: pasted) }
    }

    private func handleInputChange(_ newValue: String) {
        if let result = PastedTextAttachment.detectLargeInsertion(old: previousInputText, new: newValue) {
            pendingPastedTexts.append(PastedTextAttachment(text: result.inserted))
            inputText = result.remaining
            previousInputText = result.remaining
        } else {
            previousInputText = newValue
        }
    }

    private func loadFilePickerImages(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var loaded: [ChatImage] = []
        for url in urls.prefix(4) {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let nsImage = NSImage(contentsOf: url),
               let tiff = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                loaded.append(ChatImage(mediaType: "image/jpeg", base64: jpeg.base64EncodedString()))
            }
        }
        pendingImages.append(contentsOf: loaded)
    }

    private func loadDroppedImages(_ providers: [NSItemProvider]) {
        for provider in providers.prefix(4)
        where provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadDataRepresentation(
                forTypeIdentifier: "public.image"
            ) { data, _ in
                guard let data,
                      let nsImage = NSImage(data: data),
                      let tiff = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpeg = bitmap.representation(
                          using: .jpeg,
                          properties: [.compressionFactor: 0.85]
                      ) else { return }
                let chatImage = ChatImage(
                    mediaType: "image/jpeg",
                    base64: jpeg.base64EncodedString()
                )
                Task { @MainActor in
                    pendingImages.append(chatImage)
                }
            }
        }
    }

    private func openAssistantInMainApp() {
        NotificationCenter.default.post(
            name: .openMainAppRequested,
            object: nil,
            userInfo: ["section": SidebarItem.assistant.rawValue]
        )
    }
}

#if DEBUG
#Preview {
    ChatView(chat: Chat())
}
#endif
