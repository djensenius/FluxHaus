//
//  PrecipitationTimelineView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-03-14.
//

import SwiftUI
@preconcurrency import WeatherKit

struct PrecipitationTimelineView: View {
    let minuteForecast: [MinuteWeather]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Precipitation — Next Hour",
                systemImage: "clock.arrow.2.circlepath"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.Colors.textSecondary)
            .textCase(.uppercase)

            HStack(alignment: .bottom, spacing: 1) {
                ForEach(
                    Array(minuteForecast.prefix(60).enumerated()),
                    id: \.offset
                ) { _, minute in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: minute))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(for: minute))
                }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Text("Now")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("+30 min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("+60 min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func barHeight(for minute: MinuteWeather) -> CGFloat {
        let chance = minute.precipitationChance
        return max(2, CGFloat(chance) * 40)
    }

    private func barColor(for minute: MinuteWeather) -> Color {
        let chance = minute.precipitationChance
        if chance < 0.1 {
            return Theme.Colors.textSecondary.opacity(0.2)
        }
        if chance < 0.4 {
            return Theme.Colors.accent.opacity(0.5)
        }
        if chance < 0.7 {
            return Theme.Colors.accent.opacity(0.75)
        }
        return Theme.Colors.accent
    }
}
