//
//  RadarMapViews.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-09.
//

import MapKit
import SwiftUI

// MARK: - Static Radar Map (dashboard preview)

struct RadarMapView {
    let coordinate: CLLocationCoordinate2D
    let radarService: RadarService
    let frameIndex: Int?

    @MainActor func buildMap(delegate: MKMapViewDelegate) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = delegate
        mapView.mapType = .mutedStandard
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        #if os(macOS)
        mapView.showsZoomControls = false
        #endif
        mapView.showsCompass = false
        #if os(macOS)
        let span = MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
        #else
        let span = MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        #endif
        let region = MKCoordinateRegion(center: coordinate, span: span)
        mapView.setRegion(region, animated: false)
        let overlay = RadarAnimationOverlay(coordinate: coordinate)
        mapView.addOverlay(overlay, level: .aboveLabels)
        return mapView
    }

    @MainActor func updateMap(_ mapView: MKMapView, coordinator: StaticCoordinator) {
        let frames = radarService.allFrames
        guard !frames.isEmpty else { return }
        let idx = frameIndex ?? (radarService.pastFrames.count - 1)
        guard idx >= 0, idx < frames.count else { return }
        coordinator.renderer?.setFrame(frames[idx].path)
    }

    class StaticCoordinator: NSObject, MKMapViewDelegate {
        let radarService: RadarService
        var renderer: RadarAnimationRenderer?

        init(radarService: RadarService) {
            self.radarService = radarService
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if overlay is RadarAnimationOverlay {
                let rdr = RadarAnimationRenderer(
                    overlay: overlay,
                    urlBuilder: radarService.tileURLBuilder,
                    initialPath: radarService.latestPastFrame?.path,
                    overlayAlpha: 1.0
                )
                self.renderer = rdr
                return rdr
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

#if os(macOS)
extension RadarMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView {
        buildMap(delegate: context.coordinator)
    }
    func updateNSView(_ view: MKMapView, context: Context) {
        updateMap(view, coordinator: context.coordinator)
    }
    func makeCoordinator() -> StaticCoordinator {
        StaticCoordinator(radarService: radarService)
    }
}
#else
extension RadarMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        buildMap(delegate: context.coordinator)
    }
    func updateUIView(_ view: MKMapView, context: Context) {
        updateMap(view, coordinator: context.coordinator)
    }
    func makeCoordinator() -> StaticCoordinator {
        StaticCoordinator(radarService: radarService)
    }
}
#endif

// MARK: - Interactive Animated Radar Map

struct InteractiveRadarMapView {
    let coordinate: CLLocationCoordinate2D
    let radarService: RadarService
    let frameIndex: Int

    @MainActor func buildMap(delegate: MKMapViewDelegate) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = delegate
        mapView.mapType = .mutedStandard
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = false
        #if os(macOS)
        mapView.showsZoomControls = true
        #endif
        mapView.showsCompass = true
        #if os(macOS)
        let span = MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5)
        #else
        let span = MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
        #endif
        let region = MKCoordinateRegion(center: coordinate, span: span)
        mapView.setRegion(region, animated: false)
        let overlay = RadarAnimationOverlay(coordinate: coordinate)
        mapView.addOverlay(overlay, level: .aboveLabels)
        return mapView
    }

    @MainActor func updateMap(
        _ mapView: MKMapView,
        coordinator: AnimatedCoordinator
    ) {
        let frames = radarService.allFrames
        guard !frames.isEmpty else { return }
        let idx = min(max(frameIndex, 0), frames.count - 1)
        coordinator.renderer?.setFrame(frames[idx].path)
        if !coordinator.hasPreloaded,
           let rdr = coordinator.renderer,
           mapView.frame.width > 0 {
            rdr.preload(
                frames: frames,
                visibleRect: mapView.visibleMapRect,
                viewWidth: mapView.frame.width
            )
            coordinator.hasPreloaded = true
        }
    }

    class AnimatedCoordinator: NSObject, MKMapViewDelegate {
        let radarService: RadarService
        var renderer: RadarAnimationRenderer?
        var hasPreloaded = false

        init(radarService: RadarService) {
            self.radarService = radarService
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if overlay is RadarAnimationOverlay {
                let rdr = RadarAnimationRenderer(
                    overlay: overlay,
                    urlBuilder: radarService.tileURLBuilder,
                    initialPath: radarService.latestPastFrame?.path
                )
                self.renderer = rdr
                return rdr
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

#if os(macOS)
extension InteractiveRadarMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView {
        buildMap(delegate: context.coordinator)
    }
    func updateNSView(_ view: MKMapView, context: Context) {
        updateMap(view, coordinator: context.coordinator)
    }
    func makeCoordinator() -> AnimatedCoordinator {
        AnimatedCoordinator(radarService: radarService)
    }
}
#else
extension InteractiveRadarMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        buildMap(delegate: context.coordinator)
    }
    func updateUIView(_ view: MKMapView, context: Context) {
        updateMap(view, coordinator: context.coordinator)
    }
    func makeCoordinator() -> AnimatedCoordinator {
        AnimatedCoordinator(radarService: radarService)
    }
}
#endif
