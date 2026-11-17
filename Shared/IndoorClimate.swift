//
//  IndoorClimate.swift
//  FluxHaus
//
//  Indoor temperature sensors (thermostat + remote room sensors) reported by
//  the server under `indoorClimate` in the `GET /` snapshot.
//

import Foundation

public struct IndoorTemperatureSensor: Codable, Identifiable, Hashable, Sendable {
    public let entityId: String
    public let name: String
    /// Home Assistant area (room) the sensor is assigned to.
    public let area: String?
    public let temperature: Double?
    public let unit: String?
    public let available: Bool?
    public let occupied: Bool?
    public let isThermostat: Bool?
    public let lastUpdated: String?

    public var id: String { entityId }

    public var isAvailable: Bool { (available ?? true) && temperature != nil }

    public init(
        entityId: String,
        name: String,
        area: String? = nil,
        temperature: Double?,
        unit: String? = "°C",
        available: Bool? = true,
        occupied: Bool? = nil,
        isThermostat: Bool? = false,
        lastUpdated: String? = nil
    ) {
        self.entityId = entityId
        self.name = name
        self.area = area
        self.temperature = temperature
        self.unit = unit
        self.available = available
        self.occupied = occupied
        self.isThermostat = isThermostat
        self.lastUpdated = lastUpdated
    }
}

public struct ThermostatStatus: Codable, Hashable, Sendable {
    public let entityId: String
    public let name: String?
    public let area: String?
    public let available: Bool?
    public let currentTemperature: Double?
    public let currentHumidity: Double?
    public let hvacMode: String?
    public let hvacAction: String?
    public let targetTemperature: Double?
    public let targetTemperatureLow: Double?
    public let targetTemperatureHigh: Double?
    public let presetMode: String?
    // Control capabilities (absent on servers that predate thermostat control).
    public let hvacModes: [String]?
    public let presetModes: [String]?
    public let fanMode: String?
    public let fanModes: [String]?
    public let minTemp: Double?
    public let maxTemp: Double?
    public let targetTempStep: Double?
    /// Unit of the thermostat's readings and setpoints (Home Assistant's system unit).
    public let temperatureUnit: String?

    public init(
        entityId: String,
        name: String? = nil,
        area: String? = nil,
        available: Bool? = true,
        currentTemperature: Double? = nil,
        currentHumidity: Double? = nil,
        hvacMode: String? = nil,
        hvacAction: String? = nil,
        targetTemperature: Double? = nil,
        targetTemperatureLow: Double? = nil,
        targetTemperatureHigh: Double? = nil,
        presetMode: String? = nil,
        hvacModes: [String]? = nil,
        presetModes: [String]? = nil,
        fanMode: String? = nil,
        fanModes: [String]? = nil,
        minTemp: Double? = nil,
        maxTemp: Double? = nil,
        targetTempStep: Double? = nil,
        temperatureUnit: String? = nil
    ) {
        self.entityId = entityId
        self.name = name
        self.area = area
        self.available = available
        self.currentTemperature = currentTemperature
        self.currentHumidity = currentHumidity
        self.hvacMode = hvacMode
        self.hvacAction = hvacAction
        self.targetTemperature = targetTemperature
        self.targetTemperatureLow = targetTemperatureLow
        self.targetTemperatureHigh = targetTemperatureHigh
        self.presetMode = presetMode
        self.hvacModes = hvacModes
        self.presetModes = presetModes
        self.fanMode = fanMode
        self.fanModes = fanModes
        self.minTemp = minTemp
        self.maxTemp = maxTemp
        self.targetTempStep = targetTempStep
        self.temperatureUnit = temperatureUnit
    }
}

public struct IndoorClimateState: Codable, Sendable {
    public let timestamp: String?
    /// Temperature unit reported by the server for the whole house.
    public let reportedUnit: String?
    public let thermostat: ThermostatStatus?
    public let sensors: [IndoorTemperatureSensor]
    /// On a thermostat control response, whether the thermostat has reported the change yet.
    public let confirmed: Bool?

    enum CodingKeys: String, CodingKey {
        case timestamp, thermostat, sensors, confirmed
        case reportedUnit = "unit"
    }

    public init(
        timestamp: String? = nil,
        unit: String? = nil,
        thermostat: ThermostatStatus? = nil,
        sensors: [IndoorTemperatureSensor],
        confirmed: Bool? = nil
    ) {
        self.timestamp = timestamp
        self.reportedUnit = unit
        self.thermostat = thermostat
        self.sensors = sensors
        self.confirmed = confirmed
    }

    /// Home Assistant data can be messy, so a malformed thermostat or sensor is
    /// dropped instead of failing the whole `LoginResponse` decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
        reportedUnit = try? container.decodeIfPresent(String.self, forKey: .reportedUnit)
        thermostat = (try? container.decodeIfPresent(ThermostatStatus.self, forKey: .thermostat)) ?? nil
        let entries = try? container.decodeIfPresent(
            [LenientDecodable<IndoorTemperatureSensor>].self, forKey: .sensors
        )
        sensors = (entries ?? nil)?.compactMap(\.value) ?? []
        confirmed = try? container.decodeIfPresent(Bool.self, forKey: .confirmed)
    }
}

private struct LenientDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Derived values

public enum IndoorWarmth: Sendable {
    case warmer, typical, cooler
}

extension IndoorClimateState {
    public var hasData: Bool { thermostat != nil || !sensors.isEmpty }

    public var availableSensors: [IndoorTemperatureSensor] { sensors.filter(\.isAvailable) }

    /// Unit reported by Home Assistant (thermostat attributes share the
    /// system unit), falling back to the first sensor's unit.
    public var unit: String {
        if let reported = reportedUnit, !reported.isEmpty { return reported }
        return sensors.lazy.compactMap(\.unit).first { !$0.isEmpty } ?? "°C"
    }

    /// Sensors in display order: thermostat first, then by room name.
    public var rooms: [IndoorTemperatureSensor] {
        sensors.sorted { lhs, rhs in
            let lhsThermostat = lhs.isThermostat == true, rhsThermostat = rhs.isThermostat == true
            if lhsThermostat != rhsThermostat { return lhsThermostat }
            return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    /// The room a sensor is in, using its Home Assistant area when assigned.
    /// When two sensors share an area, the device name (or "Thermostat") is
    /// added so they stay distinguishable.
    public func displayName(for sensor: IndoorTemperatureSensor) -> String {
        guard let area = sensor.area?.trimmingCharacters(in: .whitespaces), !area.isEmpty else {
            return sensor.name
        }
        let sharesArea = sensors.contains { other in
            other.entityId != sensor.entityId
                && other.area?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(area) == .orderedSame
        }
        guard sharesArea else { return area }
        if sensor.isThermostat == true { return "\(area) Thermostat" }
        if sensor.name.caseInsensitiveCompare(area) == .orderedSame { return area }
        return "\(area) · \(sensor.name)"
    }

    public var isFahrenheit: Bool { unit.uppercased().contains("F") }

    /// Unit of the thermostat's readings and setpoints, which can differ from the
    /// sensors' when a sensor's display unit was changed in Home Assistant.
    public var thermostatUnit: String {
        if let reported = thermostat?.temperatureUnit, !reported.isEmpty { return reported }
        return unit
    }

    /// A sensor's reading converted into the home's unit, so rooms reported in
    /// °C and °F can be compared and averaged.
    public func temperature(of sensor: IndoorTemperatureSensor) -> Double? {
        sensor.temperature.map { converted($0, from: sensor.unit) }
    }

    private func converted(_ value: Double, from source: String?) -> Double {
        let source = source?.uppercased() ?? ""
        if source.contains("F") && !isFahrenheit { return (value - 32) * 5 / 9 }
        if source.contains("C") && isFahrenheit { return value * 9 / 5 + 32 }
        return value
    }

    /// The headline indoor temperature: what the thermostat reports (Ecobee
    /// averages its participating sensors), falling back to the thermostat's own
    /// sensor, then the mean of every available room.
    public var primaryTemperature: Double? {
        if thermostat?.available != false, let current = thermostat?.currentTemperature {
            return converted(current, from: thermostatUnit)
        }
        let available = availableSensors
        if let own = available.first(where: { $0.isThermostat == true }).flatMap(temperature(of:)) {
            return own
        }
        return averageTemperature
    }

    public var averageTemperature: Double? {
        let temps = availableSensors.compactMap(temperature(of:))
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    /// Coolest → warmest room, only meaningful with two or more rooms.
    public var temperatureRange: ClosedRange<Double>? {
        let temps = availableSensors.compactMap(temperature(of:))
        guard temps.count >= 2, let low = temps.min(), let high = temps.max() else { return nil }
        return low...high
    }

    /// Whether a room is noticeably warmer or cooler than the house average
    /// (±1 °C / ±1.8 °F).
    public func warmth(of sensor: IndoorTemperatureSensor) -> IndoorWarmth {
        guard availableSensors.count >= 2,
              let temp = temperature(of: sensor), sensor.isAvailable,
              let average = averageTemperature else { return .typical }
        let threshold = isFahrenheit ? 1.8 : 1.0
        if temp - average >= threshold { return .warmer }
        if average - temp >= threshold { return .cooler }
        return .typical
    }
}

// MARK: - Thermostat summary

public struct ThermostatSummary: Equatable, Sendable {
    public enum Activity: Equatable, Sendable {
        case heating, cooling, fan, idle, off, unavailable
    }

    public let activity: Activity
    public let text: String

    public var systemImage: String {
        switch activity {
        case .heating: return "flame.fill"
        case .cooling: return "snowflake"
        case .fan: return "fan.fill"
        case .idle: return "thermometer.medium"
        case .off: return "power"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    public init(thermostat: ThermostatStatus, format: (Double) -> String) {
        guard thermostat.available != false else {
            self.init(activity: .unavailable, text: "Thermostat unavailable")
            return
        }
        let mode = thermostat.hvacMode?.lowercased()
        let heatTarget = thermostat.targetTemperature ?? thermostat.targetTemperatureLow
        let coolTarget = thermostat.targetTemperature ?? thermostat.targetTemperatureHigh

        switch thermostat.hvacAction?.lowercased() {
        case "heating", "preheating":
            self.init(activity: .heating, text: Self.label("Heating", to: heatTarget, format: format))
            return
        case "cooling":
            self.init(activity: .cooling, text: Self.label("Cooling", to: coolTarget, format: format))
            return
        case "fan":
            self.init(activity: .fan, text: "Fan running")
            return
        default:
            break
        }

        self = Self.idle(mode: mode, thermostat: thermostat, heatTarget: heatTarget,
                         coolTarget: coolTarget, format: format)
    }

    private static func idle(
        mode: String?,
        thermostat: ThermostatStatus,
        heatTarget: Double?,
        coolTarget: Double?,
        format: (Double) -> String
    ) -> ThermostatSummary {
        switch mode {
        case nil:
            return ThermostatSummary(activity: .idle, text: "Status unknown")
        case "off":
            return ThermostatSummary(activity: .off, text: "Off")
        case "heat":
            return ThermostatSummary(activity: .idle, text: setpoint("Heat", heatTarget, format: format))
        case "cool":
            return ThermostatSummary(activity: .idle, text: setpoint("Cool", coolTarget, format: format))
        case let mode?:
            let modeName = mode == "heat_cool" ? "Auto" : mode.replacingOccurrences(of: "_", with: " ").capitalized
            if let low = thermostat.targetTemperatureLow, let high = thermostat.targetTemperatureHigh {
                return ThermostatSummary(activity: .idle, text: "\(modeName) · \(format(low))–\(format(high))")
            }
            let text = setpoint(modeName, thermostat.targetTemperature, format: format)
            return ThermostatSummary(activity: .idle, text: text)
        }
    }

    private init(activity: Activity, text: String) {
        self.activity = activity
        self.text = text
    }

    private static func label(_ verb: String, to target: Double?, format: (Double) -> String) -> String {
        guard let target else { return verb }
        return "\(verb) to \(format(target))"
    }

    private static func setpoint(_ mode: String, _ target: Double?, format: (Double) -> String) -> String {
        guard let target else { return mode }
        return "\(mode) · set to \(format(target))"
    }
}

// MARK: - Formatting

enum IndoorClimateFormat {
    private nonisolated(unsafe) static let formatter: MeasurementFormatter = {
        let fmt = MeasurementFormatter()
        fmt.numberFormatter.minimumFractionDigits = 1
        fmt.numberFormatter.maximumFractionDigits = 1
        return fmt
    }()

    private nonisolated(unsafe) static let compactFormatter: MeasurementFormatter = {
        let fmt = MeasurementFormatter()
        fmt.numberFormatter.minimumFractionDigits = 0
        fmt.numberFormatter.maximumFractionDigits = 1
        return fmt
    }()

    /// Formats a reading in the user's preferred unit. Indoor rooms differ by
    /// fractions of a degree, so readings always show one decimal; setpoints
    /// drop a trailing ".0" (21°, 20.5°).
    static func temperature(_ value: Double, unit: String, precise: Bool = true) -> String {
        let source: UnitTemperature = unit.uppercased().contains("F") ? .fahrenheit : .celsius
        let measurement = Measurement(value: value, unit: source)
        return (precise ? formatter : compactFormatter).string(from: measurement)
    }

    static func humidity(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
