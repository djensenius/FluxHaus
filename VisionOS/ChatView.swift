//
//  ChatView.swift
//  VisionOS
//
//  Created by David Jensenius on 2026-03-01.
//

import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            Text(message.content)
                .padding(12)
                .foregroundColor(foregroundColor)
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
            return .accentColor
        case .assistant:
            return Color(.secondarySystemBackground)
        case .error:
            return .red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user:
            return .white
        case .assistant:
            return .primary
        case .error:
            return .red
        }
    }
}

struct ChatView: View {
    @Bindable var chat: Chat
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assistant")
                    .font(.title)
                Spacer()
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chat.messages) { message in
                            ChatBubble(message: message)
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
                        if let lastMessage = chat.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
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

            Divider()

            HStack(spacing: 8) {
                TextField("Ask anything…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(
                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isLoading
                )
            }
            .padding()
        }
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task {
            await chat.send(text)
        }
    }
}

#if DEBUG
#Preview(windowStyle: .automatic) {
    ChatView(chat: Chat())
}
#endif
