//
//  TypingIndicator.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-14.
//

import SwiftUI

/// Animated typing indicator with three pulsing dots,
/// styled like iMessage in the app's Catppuccin theme.
struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.Colors.textSecondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(phase == index ? 1.3 : 0.8)
                        .offset(y: phase == index ? -4 : 0)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .delay(Double(index) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.Colors.secondaryBackground)
            )
            Spacer(minLength: 48)
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation {
                phase = (phase + 1) % 3
            }
        }
    }
}
