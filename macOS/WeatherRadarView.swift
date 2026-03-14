//
//  WeatherRadarView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-08.
//

import SwiftUI
import MapKit
@preconcurrency import WeatherKit

// MARK: - Weather Radar Sheet (macOS popup)

struct WeatherRadarSheet: View {
    let coordinate: CLLocationCoordinate2D
    let radarService: RadarService
    let weather: Weather?
    @State private var frameIndex = 0
    @State private var isPlaying = false
    @State private var animationTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                InteractiveRadarMapView(
                    coordinate: coordinate,
                    radarService: radarService,
                    frameIndex: frameIndex
                )
                .frame(minWidth: 500).frame(height: 350)
                controls
                if let weather {
                    if let minuteForecast = weather.minuteForecast,
                       !minuteForecast.isEmpty {
                        Divider()
                        PrecipitationTimelineView(
                            minuteForecast: Array(minuteForecast)
                        )
                    }
                    Divider()
                    WeatherForecastSection(weather: weather)
                }
            }
        }
        .frame(minWidth: 550, minHeight: 600)
        .onDisappear { stopAnimation() }
        .onAppear {
            frameIndex = max(0, radarService.pastFrames.count - 1)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weather Radar").font(.headline)
                if radarService.nowcastFrames.isEmpty {
                    Text("Past 50 minutes")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("50 min past + 50 min forecast")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
        }
        .padding()
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text(frameTimeLabel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer()
                if let frame = currentFrame {
                    Text(radarService.relativeLabel(for: frame))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(
                            frameIndex < radarService.pastFrames.count
                                ? .secondary : Theme.Colors.accent
                        )
                }
            }
            if let frame = currentFrame, frameIndex >= radarService.pastFrames.count {
                confidenceBar(radarService.confidence(for: frame))
            }
            HStack(spacing: 12) {
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                Text("Past")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(min(frameIndex, max(0, radarService.allFrames.count - 1))) },
                        set: { frameIndex = min(Int($0), radarService.allFrames.count - 1) }
                    ),
                    in: 0...Double(max(0, radarService.allFrames.count - 1)),
                    step: 1
                )
                Text(radarService.nowcastFrames.isEmpty ? "Now" : "Forecast")
                    .font(.caption2)
                    .foregroundColor(
                        radarService.nowcastFrames.isEmpty
                            ? .secondary : Theme.Colors.accent
                    )
            }
        }
        .padding()
    }

    private var currentFrame: RadarFrame? {
        let frames = radarService.allFrames
        guard frameIndex >= 0, frameIndex < frames.count else { return nil }
        return frames[frameIndex]
    }

    private func confidenceBar(_ value: Double) -> some View {
        HStack(spacing: 6) {
            Text("Confidence")
                .font(.caption2)
                .foregroundColor(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(confidenceColor(value))
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 6)
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private func confidenceColor(_ value: Double) -> Color {
        if value > 0.7 { return Theme.Colors.accent }
        if value > 0.5 { return Theme.Colors.warning }
        return Theme.Colors.error.opacity(0.7)
    }

    private var frameTimeLabel: String {
        let frames = radarService.allFrames
        guard frameIndex >= 0, frameIndex < frames.count else { return "" }
        let date = Date(timeIntervalSince1970: Double(frames[frameIndex].time))
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    private func togglePlay() {
        if isPlaying { stopAnimation() } else { startAnimation() }
    }

    private func startAnimation() {
        isPlaying = true
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { break }
                let total = radarService.allFrames.count
                guard total > 1 else { break }
                let next = frameIndex + 1
                if next >= total {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    frameIndex = 0
                } else {
                    frameIndex = next
                }
            }
        }
    }

    private func stopAnimation() {
        isPlaying = false
        animationTask?.cancel()
        animationTask = nil
    }
}

// MARK: - Weather Card (Compact Dashboard Card)

struct WeatherCard: View {
    @ObservedObject var locationManager: LocationManager
    var radarService: RadarService
    var onNavigate: (SidebarItem) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if radarService.isLoaded {
                RadarMapView(
                    coordinate: locationManager.coordinate,
                    radarService: radarService, frameIndex: nil
                )
                .frame(maxWidth: .infinity).frame(height: 120).clipped()
                .overlay(
                    LinearGradient(
                        colors: [
                            Theme.Colors.secondaryBackground.opacity(0.85),
                            Theme.Colors.secondaryBackground.opacity(0.6)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }
            weatherOverlay
        }
        .frame(maxWidth: .infinity).frame(height: 120)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12).clipped()
        .onTapGesture { onNavigate(.weather) }
    }

    private var weatherOverlay: some View {
        HStack(spacing: 16) {
            if let weather = locationManager.weather {
                Image(systemName: weatherIcon)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 36))
                VStack(alignment: .leading, spacing: 2) {
                    Text(temperatureString)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    HStack(spacing: 4) {
                        Text(weather.currentWeather.condition.description)
                            .font(Theme.Fonts.bodySmall)
                            .foregroundColor(Theme.Colors.textSecondary)
                        if let precipText = precipitationText {
                            Text("·")
                                .foregroundColor(Theme.Colors.textSecondary)
                            Label(precipText, systemImage: locationManager.forecast?.symbolName ?? "cloud.rain")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        }
                    }
                    if let alerts = weather.weatherAlerts, !alerts.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 10))
                            Text(alerts.map(\.summary).joined(separator: " · "))
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.error)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                if let high = highTemp, let low = lowTemp {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("H: \(high)", systemImage: "arrow.up")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Label("L: \(low)", systemImage: "arrow.down")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
                Text("Loading weather…")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding()
    }

    private var temperatureString: String {
        guard let weather = locationManager.weather else { return "" }
        return WeatherHelpers.formatTemp(weather.currentWeather.temperature.value)
    }
    private var highTemp: String? {
        guard let weather = locationManager.weather,
              let today = weather.dailyForecast.first else { return nil }
        return WeatherHelpers.formatTemp(today.highTemperature.value)
    }
    private var lowTemp: String? {
        guard let weather = locationManager.weather,
              let today = weather.dailyForecast.first else { return nil }
        return WeatherHelpers.formatTemp(today.lowTemperature.value)
    }
    private var weatherIcon: String {
        guard let weather = locationManager.weather else { return "cloud" }
        return WeatherHelpers.icon(for: weather.currentWeather.condition)
    }
    private var precipitationText: String? {
        guard let forecast = locationManager.forecast else { return nil }
        return WeatherHelpers.precipitationText(from: forecast)
    }
}
