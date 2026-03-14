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

    private var maxIntensity: Double {
        let peak = minuteForecast.prefix(60)
            .map { $0.precipitationIntensity.value }
            .max() ?? 0
        return max(peak, 0.5) // min scale of 0.5 mm/hr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    "Precipitation — Next Hour",
                    systemImage: "clock.arrow.2.circlepath"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                Spacer()
                Text(intensityLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

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

    private var intensityLabel: String {
        let peak = minuteForecast.prefix(60)
            .map { $0.precipitationIntensity.value }
            .max() ?? 0
        if peak < 0.1 { return "None" }
        if peak < 2.5 { return "Light" }
        if peak < 7.5 { return "Moderate" }
        return "Heavy"
    }

    private func barHeight(for minute: MinuteWeather) -> CGFloat {
        let intensity = minute.precipitationIntensity.value
        if intensity < 0.01 { return 2 }
        let normalized = min(intensity / maxIntensity, 1.0)
        return max(3, CGFloat(normalized) * 40)
    }

    private func barColor(for minute: MinuteWeather) -> Color {
        let intensity = minute.precipitationIntensity.value
        if intensity < 0.01 {
            return Theme.Colors.textSecondary.opacity(0.15)
        }
        let normalized = min(intensity / maxIntensity, 1.0)
        if normalized < 0.3 {
            return Theme.Colors.accent.opacity(0.4)
        }
        if normalized < 0.6 {
            return Theme.Colors.accent.opacity(0.7)
        }
        return Theme.Colors.accent
    }
}
