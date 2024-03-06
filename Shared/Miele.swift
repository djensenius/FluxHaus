//
//  HomeAPI.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import Foundation
import OAuth2
import UIKit

struct Appliance {
    let name: String
    let timeRunning: Int
    let timeRemaining: Int
    let timeFinish: String
    let step: String
    let programName: String
    let inUse: Bool
}

// MARK: - MieleAppliances
struct MieleAppliances: Codable {
    let ident: Ident
    let stateType: StateType

    enum CodingKeys: String, CodingKey {
        case ident
        case stateType = "state"
    }
}

// MARK: - Ident
struct Ident: Codable {
    let xkmIdentLabel: XkmIdentLabel
    let deviceIdentLabel: DeviceIdentLabel
    let type: TypeClass
    let deviceName: String
}

// MARK: - DeviceIdentLabel
struct DeviceIdentLabel: Codable {
    let matNumber, techType: String
    let swids: [String]
    let fabIndex, fabNumber: String
}

// MARK: - TypeClass
struct TempTypeClass: Codable {
    let keyLocalized: String?
    let valueRaw: Int?
    let valueLocalized: Float?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case keyLocalized = "key_localized"
        case valueRaw = "value_raw"
        case valueLocalized = "value_localized"
        case unit
    }
}

// MARK: - TypeClass
struct TypeClass: Codable {
    let keyLocalized: String?
    let valueRaw: Int?
    let valueLocalized: String?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case keyLocalized = "key_localized"
        case valueRaw = "value_raw"
        case valueLocalized = "value_localized"
        case unit
    }
}

// MARK: - XkmIdentLabel
struct XkmIdentLabel: Codable {
    let releaseVersion, techType: String
}

// MARK: - StateType
struct StateType: Codable {
    let dryingStep, status, programType, ventilationStep: TypeClass
    let light: Int?
    let signalDoor: Bool?
    let batteryLevel: JSONNull?
    let signalFailure: Bool?
    let plateStep: [JSONAny]
    let programID, spinningSpeed: TypeClass
    let targetTemperature: [TempTypeClass]
    let elapsedTime, startTime, remainingTime: [Int]
    let signalInfo: Bool?
    let programPhase: TypeClass
    let temperature: [TypeClass]
    let remoteEnable: RemoteEnable?

    enum CodingKeys: String, CodingKey {
        case dryingStep, status, programType, ventilationStep, light, signalDoor, batteryLevel, signalFailure, plateStep
        case programID = "ProgramID"
        case spinningSpeed, targetTemperature, elapsedTime, startTime, remainingTime, signalInfo, programPhase, temperature, remoteEnable
    }
}

// MARK: - RemoteEnable
struct RemoteEnable: Codable {
    let smartGrid, mobileStart, fullRemoteControl: Bool?
}

// MARK: - Encode/decode helpers

class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        return true
    }

    public var hashValue: Int {
        return 0
    }

    public func hash(into hasher: inout Hasher) {
        // No-op
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

class JSONCodingKey: CodingKey {
    let key: String

    required init?(intValue: Int) {
        return nil
    }

    required init?(stringValue: String) {
        key = stringValue
    }

    var intValue: Int? {
        return nil
    }

    var stringValue: String {
        return key
    }
}

class JSONAny: Codable {

    let value: Any

    static func decodingError(forCodingPath codingPath: [CodingKey]) -> DecodingError {
        let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode JSONAny")
        return DecodingError.typeMismatch(JSONAny.self, context)
    }

    static func encodingError(forValue value: Any, codingPath: [CodingKey]) -> EncodingError {
        let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Cannot encode JSONAny")
        return EncodingError.invalidValue(value, context)
    }

    static func decode(from container: SingleValueDecodingContainer) throws -> Any {
        if let value = try? container.decode(Bool.self) {
            return value
        }
        if let value = try? container.decode(Int64.self) {
            return value
        }
        if let value = try? container.decode(Double.self) {
            return value
        }
        if let value = try? container.decode(String.self) {
            return value
        }
        if container.decodeNil() {
            return JSONNull()
        }
        throw decodingError(forCodingPath: container.codingPath)
    }

    static func decode(from container: inout UnkeyedDecodingContainer) throws -> Any {
        if let value = try? container.decode(Bool.self) {
            return value
        }
        if let value = try? container.decode(Int64.self) {
            return value
        }
        if let value = try? container.decode(Double.self) {
            return value
        }
        if let value = try? container.decode(String.self) {
            return value
        }
        if let value = try? container.decodeNil() {
            if value {
                return JSONNull()
            }
        }
        if var container = try? container.nestedUnkeyedContainer() {
            return try decodeArray(from: &container)
        }
        if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self) {
            return try decodeDictionary(from: &container)
        }
        throw decodingError(forCodingPath: container.codingPath)
    }

    static func decode(from container: inout KeyedDecodingContainer<JSONCodingKey>, forKey key: JSONCodingKey) throws -> Any {
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeNil(forKey: key) {
            if value {
                return JSONNull()
            }
        }
        if var container = try? container.nestedUnkeyedContainer(forKey: key) {
            return try decodeArray(from: &container)
        }
        if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key) {
            return try decodeDictionary(from: &container)
        }
        throw decodingError(forCodingPath: container.codingPath)
    }

    static func decodeArray(from container: inout UnkeyedDecodingContainer) throws -> [Any] {
        var arr: [Any] = []
        while !container.isAtEnd {
            let value = try decode(from: &container)
            arr.append(value)
        }
        return arr
    }

    static func decodeDictionary(from container: inout KeyedDecodingContainer<JSONCodingKey>) throws -> [String: Any] {
        var dict = [String: Any]()
        for key in container.allKeys {
            let value = try decode(from: &container, forKey: key)
            dict[key.stringValue] = value
        }
        return dict
    }

    static func encode(to container: inout UnkeyedEncodingContainer, array: [Any]) throws {
        for value in array {
            if let value = value as? Bool {
                try container.encode(value)
            } else if let value = value as? Int64 {
                try container.encode(value)
            } else if let value = value as? Double {
                try container.encode(value)
            } else if let value = value as? String {
                try container.encode(value)
            } else if value is JSONNull {
                try container.encodeNil()
            } else if let value = value as? [Any] {
                var container = container.nestedUnkeyedContainer()
                try encode(to: &container, array: value)
            } else if let value = value as? [String: Any] {
                var container = container.nestedContainer(keyedBy: JSONCodingKey.self)
                try encode(to: &container, dictionary: value)
            } else {
                throw encodingError(forValue: value, codingPath: container.codingPath)
            }
        }
    }

    static func encode(to container: inout KeyedEncodingContainer<JSONCodingKey>, dictionary: [String: Any]) throws {
        for (key, value) in dictionary {
            let key = JSONCodingKey(stringValue: key)!
            if let value = value as? Bool {
                try container.encode(value, forKey: key)
            } else if let value = value as? Int64 {
                try container.encode(value, forKey: key)
            } else if let value = value as? Double {
                try container.encode(value, forKey: key)
            } else if let value = value as? String {
                try container.encode(value, forKey: key)
            } else if value is JSONNull {
                try container.encodeNil(forKey: key)
            } else if let value = value as? [Any] {
                var container = container.nestedUnkeyedContainer(forKey: key)
                try encode(to: &container, array: value)
            } else if let value = value as? [String: Any] {
                var container = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key)
                try encode(to: &container, dictionary: value)
            } else {
                throw encodingError(forValue: value, codingPath: container.codingPath)
            }
        }
    }

    static func encode(to container: inout SingleValueEncodingContainer, value: Any) throws {
        if let value = value as? Bool {
            try container.encode(value)
        } else if let value = value as? Int64 {
            try container.encode(value)
        } else if let value = value as? Double {
            try container.encode(value)
        } else if let value = value as? String {
            try container.encode(value)
        } else if value is JSONNull {
            try container.encodeNil()
        } else {
            throw encodingError(forValue: value, codingPath: container.codingPath)
        }
    }

    public required init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            self.value = try JSONAny.decodeArray(from: &arrayContainer)
        } else if var container = try? decoder.container(keyedBy: JSONCodingKey.self) {
            self.value = try JSONAny.decodeDictionary(from: &container)
        } else {
            let container = try decoder.singleValueContainer()
            self.value = try JSONAny.decode(from: container)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if let arr = self.value as? [Any] {
            var container = encoder.unkeyedContainer()
            try JSONAny.encode(to: &container, array: arr)
        } else if let dict = self.value as? [String: Any] {
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            try JSONAny.encode(to: &container, dictionary: dict)
        } else {
            var container = encoder.singleValueContainer()
            try JSONAny.encode(to: &container, value: self.value)
        }
    }
}


// MARK: - Miele

class Miele: ObservableObject {
    @Published var appliances: [Appliance] = []

    init() {
        print("Hi Miele");
        appliances = []
    }

    func fetchAppliance(appliance: String) {
        print("Fetch Miele");
        let base = URL(string: "https://api.mcs3.miele.com")!
        let url = base.appendingPathComponent("v1/devices/\(appliance)?language=en")

        var req = oauth2Miele.request(forURL: url)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
       // oauth2Miele.logger = OAuth2DebugLogger(.trace)

        loaderMiele.perform(request: req) { response in
            do {
                let decoder = JSONDecoder()
                if let mApps = try? decoder.decode(MieleAppliances.self, from: response.responseData()) {
                    let inUse = (mApps.stateType.status.valueLocalized == "Off" || mApps.stateType.status.valueLocalized == "Not connected") ? false: true
                    let programName = mApps.stateType.programID.valueLocalized
                    let currentDate = Date()
                    var finishTime: Date
                    if (mApps.stateType.remainingTime.count > 0) {
                        finishTime = Calendar.current.date(
                            byAdding: .minute,
                            value: mApps.stateType.remainingTime[1] + (60 * mApps.stateType.remainingTime[0]),
                            to: currentDate
                        ) ?? currentDate
                    } else {
                        finishTime = currentDate;
                    }
                    let formatter = DateFormatter()
                    formatter.dateFormat = "h:mm a"
                    let formatedTime = formatter.string(from: finishTime)
                    var name = mApps.ident.type.valueLocalized ?? ""
                    if (mApps.ident.type.valueLocalized == "Washing Machine") {
                        name = "Washer"
                    } else if (mApps.ident.type.valueLocalized == "Clothes Dryer") {
                        name = "Dryer"
                    }
                    var timeRemaining0 = 0
                    var timeRemaining1 = 0
                    if (mApps.stateType.remainingTime.count > 1) {
                        timeRemaining0 = mApps.stateType.remainingTime[0]
                        timeRemaining1 = mApps.stateType.remainingTime[1]
                    }

                    var elapsedTime = 0
                    if (mApps.stateType.elapsedTime.count > 1) {
                        elapsedTime = mApps.stateType.elapsedTime[1]
                    }
                    let appliance = Appliance(
                        name: name,
                        timeRunning: elapsedTime,
                        timeRemaining: (timeRemaining0 * 60) + timeRemaining1,
                        timeFinish: formatedTime,
                        step: mApps.stateType.programPhase.valueLocalized ?? "",
                        programName: programName!,
                        inUse: inUse
                    )
                    DispatchQueue.main.async {
                        var found = false
                        for (index, app) in self.appliances.enumerated() {
                            if app.name == appliance.name {
                                self.appliances[index] = appliance
                                found = true
                            }
                        }
                        if found == false {
                            self.appliances.append(appliance)
                        }
                    }
                }
            }
        }
    }
}
