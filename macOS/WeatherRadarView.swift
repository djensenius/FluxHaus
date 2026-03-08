//
//  WeatherRadarView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-08.
//

import SwiftUI
import MapKit
@preconcurrency import WeatherKit

class RadarTileOverlay: MKTileOverlay {
    let host: String
    let framePath: String

    init(host: String, framePath: String) {
        self.host = host
        self.framePath = framePath
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = false
        self.tileSize = CGSize(width: 256, height: 256)
        self.minimumZ = 1
        self.maximumZ = 7
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let urlStr = "\(host)\(framePath)/256/\(path.z)/\(path.x)/\(path.y)/6/1_1.png"
        return URL(string: urlStr)!
    }
}

struct RadarMapView: NSViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let radarService: RadarService
    let frameIndex: Int?

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsZoomControls = false
        mapView.showsCompass = false
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)
        )
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let frames = radarService.allFrames
        guard !frames.isEmpty else { return }
        let idx = frameIndex ?? (radarService.pastFrames.count - 1)
        guard idx >= 0, idx < frames.count else { return }
        let frame = frames[idx]
        let currentPath = context.coordinator.currentPath
        guard currentPath != frame.path else { return }
        mapView.removeOverlays(mapView.overlays)
        let overlay = RadarTileOverlay(host: radarService.host, framePath: frame.path)
        mapView.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.currentPath = frame.path
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var currentPath: String?

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct InteractiveRadarMapView: NSViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let radarService: RadarService
    let frameIndex: Int

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = false
        mapView.showsZoomControls = true
        mapView.showsCompass = true
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 4.0, longitudeDelta: 4.0)
        )
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        let frames = radarService.allFrames
        guard frameIndex >= 0, frameIndex < frames.count else { return }
        let frame = frames[frameIndex]
        guard frame.path != context.coordinator.currentPath else { return }

        let newOverlay = RadarTileOverlay(
            host: radarService.host, framePath: frame.path
        )
        mapView.addOverlay(newOverlay, level: .aboveLabels)

        // Delay stale overlay removal so new tiles load first
        let stalePaths = mapView.overlays.compactMap {
            ($0 as? RadarTileOverlay)?.framePath
        }.filter { $0 != frame.path }
        context.coordinator.currentPath = frame.path

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let toRemove = mapView.overlays.filter {
                guard let path = ($0 as? RadarTileOverlay)?.framePath else {
                    return false
                }
                return stalePaths.contains(path)
            }
            mapView.removeOverlays(toRemove)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var currentPath: String?

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

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
                    Text("Forecast unavailable — no active precipitation")
                        .font(.caption2).foregroundColor(.secondary)
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
                Text(relativeTimeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(
                        frameIndex < radarService.pastFrames.count
                            ? .secondary : Theme.Colors.accent
                    )
            }
            HStack(spacing: 12) {
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                Slider(
                    value: Binding(
                        get: { Double(frameIndex) },
                        set: { frameIndex = Int($0) }
                    ),
                    in: 0...Double(max(0, radarService.allFrames.count - 1)),
                    step: 1
                )
            }
        }
        .padding()
    }

    private var frameTimeLabel: String {
        let frames = radarService.allFrames
        guard frameIndex >= 0, frameIndex < frames.count else { return "" }
        let date = Date(timeIntervalSince1970: Double(frames[frameIndex].time))
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    private var relativeTimeLabel: String {
        let frames = radarService.allFrames
        guard frameIndex >= 0, frameIndex < frames.count else { return "" }
        let frameTime = Double(frames[frameIndex].time)
        let minutes = Int((frameTime - Date().timeIntervalSince1970) / 60)
        if minutes == 0 { return "Now" }
        let prefix = minutes > 0 ? "+" : ""
        return "\(prefix)\(minutes) min"
    }

    private func togglePlay() {
        if isPlaying { stopAnimation() } else { startAnimation() }
    }

    private func startAnimation() {
        isPlaying = true
        animationTask = Task {
            while !Task.isCancelled {
                let total = radarService.allFrames.count
                guard total > 1 else { break }
                let nextIndex = (frameIndex + 1) % total
                let looping = nextIndex == 0
                if looping {
                    try? await Task.sleep(for: .seconds(2))
                }
                guard !Task.isCancelled else { break }
                frameIndex = nextIndex
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func stopAnimation() {
        isPlaying = false
        animationTask?.cancel()
        animationTask = nil
    }
}

// MARK: - Weather Section (Dashboard Card)

struct WeatherCard: View {
    @ObservedObject var locationManager: LocationManager
    var radarService: RadarService
    @Binding var showRadarSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weather")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            if let weather = locationManager.weather {
                currentConditions(weather: weather)
                Divider()
                detailsRow(weather: weather)
                if let precipText = precipitationText {
                    Label(precipText, systemImage: locationManager.forecast?.symbolName ?? "cloud.rain")
                        .font(Theme.Fonts.caption).foregroundColor(Theme.Colors.accent)
                }
                Divider()
                HourlyForecastRow(weather: weather).padding(.horizontal, -16)
                Divider()
                radarPreview
                Divider()
                footerButton
            } else {
                loadingPlaceholder
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
        .sheet(isPresented: $showRadarSheet) {
            WeatherRadarSheet(
                coordinate: locationManager.coordinate,
                radarService: radarService,
                weather: locationManager.weather
            )
        }
    }

    private func currentConditions(weather: Weather) -> some View {
        HStack(spacing: 16) {
            Image(systemName: weatherIcon)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 42))
            VStack(alignment: .leading, spacing: 4) {
                Text(temperatureString)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(weather.currentWeather.condition.description)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
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
        }
    }

    private func detailsRow(weather: Weather) -> some View {
        HStack(spacing: 16) {
            weatherDetail(icon: "thermometer.medium", label: "Feels like", value: feelsLikeString)
            weatherDetail(icon: "humidity", label: "Humidity", value: humidityString)
            weatherDetail(icon: "sun.max.trianglebadge.exclamationmark", label: "UV", value: uvIndexString)
            weatherDetail(icon: "wind", label: "Wind", value: windString)
        }
    }

    private var radarPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            if radarService.isLoaded {
                RadarMapView(
                    coordinate: locationManager.coordinate,
                    radarService: radarService, frameIndex: nil
                )
                .frame(maxWidth: .infinity).frame(height: 120)
                .cornerRadius(8).clipped()
                .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Colors.background.opacity(0.5))
                    .frame(maxWidth: .infinity).frame(height: 120)
                    .overlay {
                        Label("Loading radar…", systemImage: "antenna.radiowaves.left.and.right")
                            .font(Theme.Fonts.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
            }
        }
    }

    private var footerButton: some View {
        HStack {
            Spacer()
            Button(action: { showRadarSheet = true }, label: {
                Label("Full Forecast & Radar", systemImage: "map")
                    .font(Theme.Fonts.bodyMedium)
            })
            .buttonStyle(.plain).foregroundColor(Theme.Colors.accent)
        }
    }

    private var loadingPlaceholder: some View {
        HStack {
            ProgressView().controlSize(.small)
            Text("Loading weather…")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func weatherDetail(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundColor(Theme.Colors.textSecondary)
            Text(value).font(Theme.Fonts.bodySmall).foregroundColor(Theme.Colors.textPrimary)
            Text(label).font(.system(size: 9)).foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computed properties
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
    private var feelsLikeString: String {
        guard let weather = locationManager.weather else { return "" }
        return WeatherHelpers.formatTemp(weather.currentWeather.apparentTemperature.value)
    }
    private var humidityString: String {
        guard let weather = locationManager.weather else { return "" }
        return "\(Int(weather.currentWeather.humidity * 100))%"
    }
    private var uvIndexString: String {
        guard let weather = locationManager.weather else { return "" }
        return "\(weather.currentWeather.uvIndex.value)"
    }
    private var windString: String {
        guard let weather = locationManager.weather else { return "" }
        return WeatherHelpers.formatSpeed(weather.currentWeather.wind.speed.value)
    }
    private var precipitationText: String? {
        guard let forecast = locationManager.forecast else { return nil }
        return WeatherHelpers.precipitationText(from: forecast)
    }
}
