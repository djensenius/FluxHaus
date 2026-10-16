//
//  WidgetReloader.swift
//  FluxHaus
//
//  Shared by the iOS, macOS and visionOS apps (not the widget extensions).
//

import WidgetKit

/// Pushes fresh data to widgets (Home Screen, StandBy, CarPlay, Mac desktop, visionOS) whenever the app sees
/// a meaningful change, so widgets don't have to wait for their own refresh budget.
@MainActor
enum WidgetReloader {
    private static var lastKey: String?

    static func reloadIfChanged(devices: [WidgetDevice], car: CarDetails?) {
        let key = changeKey(devices: devices, car: car)
        guard key != lastKey else { return }
        lastKey = key
        reloadAll()
    }

    /// Widget timelines and Control Center controls refresh independently.
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
        #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(macOS)
        ControlCenter.shared.reloadAllControls()
        #endif
    }

    /// Everything the widgets display. Timing is reduced to whether it's known (exact
    /// values drift with "now"), and the car's lock/climate/charging/openings are
    /// included because the car's WidgetDevice only carries battery and range.
    private static func changeKey(devices: [WidgetDevice], car: CarDetails?) -> String {
        let deviceKey = devices.map { device in
            [
                device.name, String(device.progress), device.shortText, device.trailingText,
                String(device.running), device.battery.map(String.init) ?? "-",
                device.programName ?? "-", device.endsAt == nil ? "untimed" : "timed"
            ].joined(separator: "|")
        }
        let carKey = car.map { car in
            let doors = car.doorsOpen
            return [
                car.batteryLevel, car.distance, car.locked ? 1 : 0, car.hvac ? 1 : 0,
                car.pluggedIn ? 1 : 0, car.batteryCharge ? 1 : 0, car.trunkOpen ? 1 : 0,
                car.hoodOpen ? 1 : 0, doors.frontLeft, doors.frontRight, doors.backLeft, doors.backRight
            ].map(String.init).joined(separator: "|")
        } ?? "no-car"
        return (deviceKey + [carKey]).joined(separator: "\n")
    }

    /// Signed out: forget what we showed so widgets re-fetch (and blank) immediately.
    static func reset() {
        lastKey = nil
        reloadAll()
    }
}

extension WidgetReloader {
    /// Convenience for app data updates.
    static func reloadIfChanged(response: LoginResponse) {
        let data = convertLoginResponseToAppData(response: response)
        reloadIfChanged(devices: convertDataToWidgetDevices(fluxData: data), car: data.car)
    }
}
