//
//  SuggestionChips.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-08.
//

import SwiftUI

struct SuggestionChip: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let command: String
}

let defaultSuggestions: [SuggestionChip] = [
    SuggestionChip(label: "Home status", icon: "house", command: "What's the home status?"),
    SuggestionChip(label: "Start BroomBot", icon: "fan", command: "Start the broombot"),
    SuggestionChip(label: "Appliances", icon: "washer", command: "Check the appliances"),
    SuggestionChip(label: "Car status", icon: "bolt.car", command: "What's the car status?"),
    SuggestionChip(
        label: "Driving stats",
        icon: "chart.bar",
        command: "How many km have I driven this month, broken down by week?"
    ),
    SuggestionChip(label: "Deep clean", icon: "sparkles", command: "Start a deep clean"),
    SuggestionChip(label: "Lock car", icon: "lock", command: "Lock the car")
]

struct SuggestionChipsView: View {
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(defaultSuggestions) { chip in
                    Button(
                        action: { onSelect(chip.command) },
                        label: {
                            Label(chip.label, systemImage: chip.icon)
                                .font(Theme.Fonts.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.Colors.secondaryBackground)
                                .foregroundColor(Theme.Colors.accent)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            Theme.Colors.accent.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

#if DEBUG
#Preview {
    SuggestionChipsView { command in
        print("Selected: \(command)")
    }
    .padding()
    .background(Theme.Colors.background)
}
#endif
