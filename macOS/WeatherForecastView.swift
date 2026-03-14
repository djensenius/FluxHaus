//
//  WeatherForecastView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-08.
//

// swiftlint:disable file_length
import SwiftUI
@preconcurrency import WeatherKit

// MARK: - Hourly Forecast Row

struct HourlyForecastRow: View {
    let weather: Weather

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<24, id: \.self) { index in
                    let hour = weather.hourlyForecast[index]
                    VStack(spacing: 6) {
                        Text(hourLabel(for: hour.date, index: index))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Image(systemName: WeatherHelpers.icon(for: hour.condition))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 18))
                        Text(WeatherHelpers.formatTemp(hour.temperature.value))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                        if hour.precipitationChance > 0.05 {
                            Text("\(Int(hour.precipitationChance * 100))%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.Colors.info)
                        }
                    }
                    .frame(width: 48)
                }
            }
            .padding(.horizontal)
        }
    }

    private func hourLabel(for date: Date, index: Int) -> String {
        if index == 0 { return "Now" }
        let fmt = DateFormatter()
        fmt.dateFormat = "ha"
        return fmt.string(from: date).lowercased()
    }
}

// MARK: - Daily Forecast List

struct DailyForecastList: View {
    let weather: Weather

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<min(10, weather.dailyForecast.count), id: \.self) { idx in
                let day = weather.dailyForecast[idx]
                dailyRow(day: day, index: idx)
                if idx < min(10, weather.dailyForecast.count) - 1 {
                    Divider().padding(.horizontal)
                }
            }
        }
    }

    private func dailyRow(day: DayWeather, index: Int) -> some View {
        HStack {
            Text(dayLabel(for: day.date, index: index))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 44, alignment: .leading)
            Image(systemName: WeatherHelpers.icon(for: day.condition))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 16))
                .frame(width: 28)
            precipBadge(chance: day.precipitationChance)
                .frame(width: 40)
            Spacer()
            tempBar(low: day.lowTemperature.value, high: day.highTemperature.value)
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    private func dayLabel(for date: Date, index: Int) -> String {
        if index == 0 { return "Today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }

    private func precipBadge(chance: Double) -> some View {
        Group {
            if chance > 0.05 {
                Text("\(Int(chance * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.info)
            } else {
                Text("")
            }
        }
    }

    private func tempBar(low: Double, high: Double) -> some View {
        let allDays = Array(weather.dailyForecast.prefix(10))
        let minTemp = allDays.map(\.lowTemperature.value).min() ?? low
        let maxTemp = allDays.map(\.highTemperature.value).max() ?? high
        let range = max(maxTemp - minTemp, 1)

        return HStack(spacing: 6) {
            Text(WeatherHelpers.formatTemp(low))
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 32, alignment: .trailing)
            GeometryReader { geo in
                let totalW = geo.size.width
                let startFrac = (low - minTemp) / range
                let endFrac = (high - minTemp) / range
                let barStart = totalW * startFrac
                let barWidth = max(totalW * (endFrac - startFrac), 4)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(tempGradient)
                        .frame(width: barWidth, height: 4)
                        .offset(x: barStart)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 80, height: 16)
            Text(WeatherHelpers.formatTemp(high))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(width: 32, alignment: .leading)
        }
    }

    private var tempGradient: LinearGradient {
        LinearGradient(colors: [Theme.Colors.info, Theme.Colors.warning], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Combined Forecast Section

struct WeatherForecastSection: View {
    let weather: Weather

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Hourly Forecast", icon: "clock")
            HourlyForecastRow(weather: weather)
            Divider().padding(.horizontal)
            sectionHeader("10-Day Forecast", icon: "calendar")
            DailyForecastList(weather: weather)
        }
        .padding(.vertical)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal)
    }
}

// MARK: - Weather Detail View (Sidebar Section)

struct WeatherDetailView: View {
    @ObservedObject var locationManager: LocationManager
    var radarService: RadarService
    @State private var frameIndex = 0
    @State private var isPlaying = false
    @State private var animationTask: Task<Void, Never>?
    @State private var tilesReady = false
    @State private var showFullRadar = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let weather = locationManager.weather {
                    currentWeatherCard(weather: weather)
                    if let alerts = weather.weatherAlerts, !alerts.isEmpty {
                        weatherAlertsCard(alerts: alerts)
                    }
                    radarCard
                    precipitationTimelineCard(weather: weather)
                    forecastCard(weather: weather)
                } else {
                    loadingView
                }
            }
            .padding()
        }
        .onDisappear { stopAnimation() }
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
        .task {
            await locationManager.startMonitoring()
            await locationManager.fetchTheWeather()
            await radarService.fetchFrames()
            frameIndex = max(0, radarService.pastFrames.count - 1)
        }
    }

    private func currentWeatherCard(weather: Weather) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: WeatherHelpers.icon(for: weather.currentWeather.condition))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 48))
                VStack(alignment: .leading, spacing: 4) {
                    Text(WeatherHelpers.formatTemp(weather.currentWeather.temperature.value))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(weather.currentWeather.condition.description)
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                if let today = weather.dailyForecast.first {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label(
                            "H: \(WeatherHelpers.formatTemp(today.highTemperature.value))",
                            systemImage: "arrow.up"
                        )
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                        Label(
                            "L: \(WeatherHelpers.formatTemp(today.lowTemperature.value))",
                            systemImage: "arrow.down"
                        )
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
            detailsGrid(weather: weather)
            if let forecast = locationManager.forecast,
               let text = WeatherHelpers.precipitationText(from: forecast) {
                Label(text, systemImage: forecast.symbolName)
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.accent)
                    .padding(.top, 4)
            }
        }
        .padding()
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
        #if os(visionOS)
        .glassBackgroundEffect()
        #endif
    }

    private func detailsGrid(weather: Weather) -> some View {
        let cur = weather.currentWeather
        return HStack(spacing: 16) {
            detailItem(icon: "thermometer.medium", label: "Feels like",
                       value: WeatherHelpers.formatTemp(cur.apparentTemperature.value))
            detailItem(icon: "humidity", label: "Humidity", value: "\(Int(cur.humidity * 100))%")
            detailItem(icon: "sun.max.trianglebadge.exclamationmark", label: "UV",
                       value: "\(cur.uvIndex.value)")
            detailItem(icon: "wind", label: "Wind",
                       value: WeatherHelpers.formatSpeed(cur.wind.speed.value))
        }
    }

    private func detailItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundColor(Theme.Colors.textSecondary)
            Text(value).font(Theme.Fonts.bodySmall).foregroundColor(Theme.Colors.textPrimary)
            Text(label).font(.system(size: 9)).foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @State private var selectedAlertURL: URL?

    private func weatherAlertsCard(alerts: [WeatherAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Weather Alerts", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Colors.error)
                .textCase(.uppercase)
                .padding(.horizontal)
            ForEach(alerts, id: \.summary) { alert in
                Button {
                    selectedAlertURL = alert.detailsURL
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.summary)
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                            if let region = alert.region {
                                Text("\(alert.severity.description.capitalized) · \(region)")
                                    .font(Theme.Fonts.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                            Text("Source: \(alert.source)")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical)
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
        #if os(visionOS)
        .glassBackgroundEffect()
        #endif
        .sheet(item: $selectedAlertURL) { url in
            NavigationStack {
                AlertWebView(url: url)
                    .ignoresSafeArea(.container, edges: .bottom)
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedAlertURL = nil }
                        }
                    }
                    #else
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedAlertURL = nil }
                        }
                    }
                    #endif
            }
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
            #endif
        }
    }

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Radar", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if radarService.isLoaded {
                    Button(action: { showFullRadar = true }) {
                        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                            .foregroundColor(Theme.Colors.accent)
                    }
                    .buttonStyle(.borderless)
                }
            }
            if radarService.isLoaded {
                InteractiveRadarMapView(
                    coordinate: locationManager.coordinate,
                    radarService: radarService,
                    frameIndex: frameIndex,
                    onPreloadComplete: { tilesReady = true }
                )
                .frame(maxWidth: .infinity).frame(height: 300)
                .cornerRadius(8).clipped()
                radarControls
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Colors.background.opacity(0.5))
                    .frame(maxWidth: .infinity).frame(height: 300)
                    .overlay { ProgressView("Loading radar…").font(Theme.Fonts.caption) }
            }
        }
        .padding()
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
        #if os(visionOS)
        .glassBackgroundEffect()
        #endif
        .sheet(isPresented: $showFullRadar) {
            fullRadarSheet
        }
    }

    private var fullRadarSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Weather Radar").font(.headline)
                Spacer()
                Button("Done") { showFullRadar = false }
            }
            .padding()
            InteractiveRadarMapView(
                coordinate: locationManager.coordinate,
                radarService: radarService,
                frameIndex: frameIndex
            )
            radarControls.padding()
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 550)
        #endif
    }

    private var currentFrame: RadarFrame? {
        let frames = radarService.allFrames
        guard frameIndex >= 0, frameIndex < frames.count else { return nil }
        return frames[frameIndex]
    }

    private var radarControls: some View {
        VStack(spacing: 6) {
            HStack {
                Text(frameTimeLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer()
                if let frame = currentFrame {
                    HStack(spacing: 6) {
                        confidenceLabel(for: frame)
                        Text("·").foregroundColor(.secondary)
                        Text(radarService.relativeLabel(for: frame))
                            .foregroundColor(
                                frameIndex < radarService.pastFrames.count
                                    ? .secondary : Theme.Colors.accent
                            )
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            HStack(spacing: 10) {
                if tilesReady {
                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Slider(
                    value: Binding(
                        get: { Double(min(frameIndex, max(0, radarService.allFrames.count - 1))) },
                        set: { frameIndex = min(Int($0), radarService.allFrames.count - 1) }
                    ),
                    in: 0...Double(max(0, radarService.allFrames.count - 1)),
                    step: 1
                )
            }
        }
    }

    @ViewBuilder
    private func confidenceLabel(for frame: RadarFrame) -> some View {
        if frameIndex < radarService.pastFrames.count {
            Text("Observed")
                .foregroundColor(.secondary)
        } else {
            let value = radarService.confidence(for: frame)
            let label = value > 0.7 ? "High"
                : value > 0.5 ? "Medium" : "Low"
            let color = value > 0.7 ? Theme.Colors.accent
                : value > 0.5 ? Theme.Colors.warning : Theme.Colors.error
            Text(label)
                .foregroundColor(color)
        }
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
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { break }
                let total = radarService.allFrames.count
                guard total > 1 else { break }
                let next = frameIndex + 1
                if next >= total {
                    try? await Task.sleep(for: .seconds(1.5))
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

    @ViewBuilder
    private func precipitationTimelineCard(weather: Weather) -> some View {
        if let minuteData = weather.minuteForecast, !minuteData.isEmpty {
            PrecipitationTimelineView(minuteForecast: Array(minuteData))
                .padding()
                #if !os(visionOS)
                .background(Theme.Colors.secondaryBackground)
                #endif
                .cornerRadius(12)
                #if os(visionOS)
                .glassBackgroundEffect()
                #endif
        }
    }

    private func forecastCard(weather: Weather) -> some View {
        WeatherForecastSection(weather: weather)
            #if !os(visionOS)
            .background(Theme.Colors.secondaryBackground)
            #endif
            .cornerRadius(12)
            #if os(visionOS)
            .glassBackgroundEffect()
            #endif
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading weather…")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
