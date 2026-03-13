//
//  ChatBubble.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-13.
//

import SwiftUI

// MARK: - Bubble shape with tail

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6
        var path = Path()

        if isUser {
            // User bubble: tail on bottom-right
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - tailSize))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius - tailSize),
                radius: radius, startAngle: .degrees(0), endAngle: .degrees(60), clockwise: false
            )
            // Tail
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX + tailSize - 2, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY - 4)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY - tailSize),
                control: CGPoint(x: rect.maxX - 4, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY - tailSize))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - tailSize - radius),
                radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
        } else {
            // Assistant bubble: tail on bottom-left
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tailSize - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - tailSize - radius),
                radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY - tailSize))
            // Tail
            path.addQuadCurve(
                to: CGPoint(x: rect.minX - tailSize + 2, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY - 4)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - tailSize - radius),
                control: CGPoint(x: rect.minX + 4, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Image thumbnail grid

struct ChatImageGrid: View {
    let images: [ChatImage]
    let maxHeight: CGFloat

    var body: some View {
        if images.count == 1, let img = images.first, let data = img.uiImageData {
            imageView(from: data)
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(images) { img in
                    if let data = img.uiImageData {
                        imageView(from: data)
                            .frame(height: maxHeight / 2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func imageView(from data: Data) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        #endif
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    let message: ChatMessage
    let isLastProgress: Bool
    let isPlaying: Bool
    let onPlayTapped: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Image attachments
                if !message.images.isEmpty {
                    ChatImageGrid(images: message.images, maxHeight: 220)
                }

                // Message content
                if message.isProgress {
                    progressContent
                } else if message.role == .assistant {
                    MarkdownContentView(content: message.content, role: .assistant)
                        .textSelection(.enabled)
                } else if message.role == .error {
                    Text(message.content)
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundColor(Theme.Colors.error)
                } else {
                    Text(markdownAttributed(message.content))
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundColor(Theme.Colors.background)
                }

                // Voice playback button
                if message.isVoice && message.audioData != nil {
                    playButton
                }
            }
            .padding(.horizontal, message.isProgress ? 8 : 14)
            .padding(.vertical, message.isProgress ? 6 : 12)
            .background(bubbleBackground)

            if message.role != .user { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Sub-views

    private var progressContent: some View {
        HStack(spacing: 8) {
            if isLastProgress {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Text(message.content)
                .font(Theme.Fonts.bodySmall).italic()
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var playButton: some View {
        Button(action: onPlayTapped) {
            HStack(spacing: 4) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.caption)
                Text(isPlaying ? "Stop" : "Play")
                    .font(Theme.Fonts.caption)
            }
            .foregroundColor(playButtonColor)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isProgress {
            Color.clear
        } else {
            switch message.role {
            case .user:
                BubbleShape(isUser: true)
                    .fill(Theme.Colors.accent)
            case .assistant:
                #if os(visionOS)
                BubbleShape(isUser: false)
                    .fill(.ultraThinMaterial)
                #else
                BubbleShape(isUser: false)
                    .fill(Theme.Colors.secondaryBackground)
                #endif
            case .error:
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.Colors.error.opacity(0.15))
            }
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
    ScrollView {
        VStack(spacing: 12) {
            ChatBubble(
                message: ChatMessage(role: .user, content: "What's the weather like?"),
                isLastProgress: false,
                isPlaying: false,
                onPlayTapped: {}
            )
            ChatBubble(
                message: ChatMessage(
                    role: .assistant,
                    content: "## Current Weather\n\nIt's **22°C** and sunny.\n\n- UV Index: High\n- Wind: 15 km/h\n\n```\nForecast: Clear skies all day\n```"
                ),
                isLastProgress: false,
                isPlaying: false,
                onPlayTapped: {}
            )
        }
        .padding()
    }
    .background(Theme.Colors.background)
}
#endif
