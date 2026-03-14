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

    private var minutes: [MinuteWeather] {
        Array(minuteForecast.prefix(60))
    }

    private var maxIntensity: Double {
        max(minutes.map { $0.precipitationIntensity.value }.max() ?? 0, 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaryText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)

            ZStack(alignment: .bottom) {
                // Area chart
                PrecipitationShape(
                    values: minutes.map { $0.precipitationIntensity.value },
                    maxValue: maxIntensity
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Colors.accent.opacity(0.6),
                            Theme.Colors.accent.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line on top
                PrecipitationLine(
                    values: minutes.map { $0.precipitationIntensity.value },
                    maxValue: maxIntensity
                )
                .stroke(Theme.Colors.accent, lineWidth: 2)

                // Baseline
                Rectangle()
                    .fill(Theme.Colors.textSecondary.opacity(0.15))
                    .frame(height: 1)
                    .offset(y: -0.5)
            }
            .frame(height: 50)

            // Time markers
            HStack {
                Text("Now")
                Spacer()
                Text("+15m")
                Spacer()
                Text("+30m")
                Spacer()
                Text("+45m")
                Spacer()
                Text("+60m")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private var summaryText: String {
        let isRainingNow = minutes.first.map {
            $0.precipitationIntensity.value > 0.01
        } ?? false

        if isRainingNow {
            if let stopIdx = minutes.firstIndex(where: {
                $0.precipitationIntensity.value < 0.01
            }) {
                return "Rain stopping in \(stopIdx) min"
            }
            return intensityWord + " rain for the next hour"
        } else {
            if let startIdx = minutes.firstIndex(where: {
                $0.precipitationIntensity.value > 0.01
            }) {
                return "Rain starting in \(startIdx) min"
            }
            return "No rain expected this hour"
        }
    }

    private var intensityWord: String {
        let peak = minutes.map { $0.precipitationIntensity.value }.max() ?? 0
        if peak < 2.5 { return "Light" }
        if peak < 7.5 { return "Moderate" }
        return "Heavy"
    }
}

// MARK: - Chart shapes

private struct PrecipitationShape: Shape {
    let values: [Double]
    let maxValue: Double

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        var path = Path()
        let step = rect.width / CGFloat(values.count - 1)

        path.move(to: CGPoint(x: 0, y: rect.height))
        for (idx, val) in values.enumerated() {
            let xPos = CGFloat(idx) * step
            let normalized = min(val / maxValue, 1.0)
            let yPos = rect.height * (1.0 - CGFloat(normalized))
            if idx == 0 {
                path.addLine(to: CGPoint(x: xPos, y: yPos))
            } else {
                let prev = CGFloat(idx - 1) * step
                let mid = (prev + xPos) / 2
                let prevVal = min(values[idx - 1] / maxValue, 1.0)
                let prevY = rect.height * (1.0 - CGFloat(prevVal))
                path.addCurve(
                    to: CGPoint(x: xPos, y: yPos),
                    control1: CGPoint(x: mid, y: prevY),
                    control2: CGPoint(x: mid, y: yPos)
                )
            }
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct PrecipitationLine: Shape {
    let values: [Double]
    let maxValue: Double

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        var path = Path()
        let step = rect.width / CGFloat(values.count - 1)

        for (idx, val) in values.enumerated() {
            let xPos = CGFloat(idx) * step
            let normalized = min(val / maxValue, 1.0)
            let yPos = rect.height * (1.0 - CGFloat(normalized))
            if idx == 0 {
                path.move(to: CGPoint(x: xPos, y: yPos))
            } else {
                let prev = CGFloat(idx - 1) * step
                let mid = (prev + xPos) / 2
                let prevVal = min(values[idx - 1] / maxValue, 1.0)
                let prevY = rect.height * (1.0 - CGFloat(prevVal))
                path.addCurve(
                    to: CGPoint(x: xPos, y: yPos),
                    control1: CGPoint(x: mid, y: prevY),
                    control2: CGPoint(x: mid, y: yPos)
                )
            }
        }
        return path
    }
}
