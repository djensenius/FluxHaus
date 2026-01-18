//
//  CarDetailView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import SwiftUI
import WeatherKit
import CoreLocation

struct CarDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    var car: Car
    @ObservedObject var locationManager: LocationManager
    @State private var buttonsDisabled: Bool = false
    @State var apiResponse: Api?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "car.fill")
                        Text("Car")
                    }
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.top)

                    // Status Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("EV Data Updated \(getCarTime(strDate: car.vehicle.evStatusTimestamp))")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                            Text("Battery: \(car.vehicle.batteryLevel)%, \(car.vehicle.distance) km")
                                .font(Theme.Fonts.bodyLarge)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        HStack(spacing: 16) {
                            if car.vehicle.pluggedIn {
                                Label("Plugged in", systemImage: "powerplug.fill")
                                    .foregroundColor(Theme.Colors.success)
                            } else {
                                Label("Unplugged", systemImage: "powerplug")
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            if car.vehicle.batteryCharge {
                                Label("Charging", systemImage: "bolt.fill")
                                    .foregroundColor(Theme.Colors.success)
                            } else {
                                Label("Not charging", systemImage: "bolt.slash")
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                        .font(Theme.Fonts.bodyMedium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)

                    // Details Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            let odometer = car.vehicle.odometer.formatted(
                                .number.grouping(.automatic).precision(.fractionLength(0))
                            )
                            Text("Odometer: \(odometer) km")
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }

                        HStack(spacing: 16) {
                            if car.vehicle.trunkOpen {
                                Label("Trunk open", systemImage: "car.circle.fill")
                                    .foregroundColor(Theme.Colors.error)
                            } else {
                                Label("Trunk closed", systemImage: "car.circle")
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            if car.vehicle.hoodOpen {
                                Label("Hood open", systemImage: "car.circle.fill")
                                    .foregroundColor(Theme.Colors.error)
                            } else {
                                Label("Hood closed", systemImage: "car.circle")
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                        .font(Theme.Fonts.bodyMedium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)

                    // Controls Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controls")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(spacing: 12) {
                            if car.vehicle.hvac {
                                Button(action: { performAction(action: "stop") }, label: {
                                    Text("Turn Climate Off")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red.opacity(0.2))
                                        .foregroundColor(.red)
                                        .cornerRadius(8)
                                })
                                .disabled(self.buttonsDisabled)
                            } else {
                                Button(action: { performAction(action: "start") }, label: {
                                    Text("Start Climate")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Theme.Colors.accent.opacity(0.2))
                                        .foregroundColor(Theme.Colors.accent)
                                        .cornerRadius(8)
                                })
                                .disabled(self.buttonsDisabled)

                                // Show what will happen (Auto Logic)
                                if let weather = locationManager.weather {
                                    HStack {
                                        Image(systemName: "thermometer.snowflake")
                                        Text(getClimateSummary(weather: weather))
                                    }
                                    .font(Theme.Fonts.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, 4)
                                }

                                NavigationLink(
                                    destination: CarClimateView(car: car, locationManager: locationManager)
                                ) {
                                    HStack {
                                        Text("Climate Settings")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .cornerRadius(8)
                                }
                            }

                            HStack(spacing: 12) {
                                if car.vehicle.locked {
                                    Button(action: { performAction(action: "unlock") }, label: {
                                        Label("Unlock", systemImage: "lock.open.fill")
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Theme.Colors.secondaryBackground)
                                            .foregroundColor(Theme.Colors.textPrimary)
                                            .cornerRadius(8)
                                    })
                                    .disabled(self.buttonsDisabled)
                                } else {
                                    Button(action: { performAction(action: "lock") }, label: {
                                        Label("Lock", systemImage: "lock.fill")
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(Theme.Colors.secondaryBackground)
                                            .foregroundColor(Theme.Colors.textPrimary)
                                            .cornerRadius(8)
                                    })
                                    .disabled(self.buttonsDisabled)
                                }

                                Button(action: { performAction(action: "rsync") }, label: {
                                    Label("Resync", systemImage: "arrow.triangle.2.circlepath")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                        .cornerRadius(8)
                                })
                                .disabled(self.buttonsDisabled)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)

                    if self.buttonsDisabled {
                        HStack {
                            ProgressView()
                            Text("Updating...")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
    }

    func getClimateSummary(weather: Weather) -> String {
        let temp = weather.currentWeather.temperature.converted(to: .celsius).value
        let targetTemp = temp < 25 ? 21 : 24

        var featureList: [String] = []
        if temp < 0 {
            featureList = ["Seats", "Steering", "Defrost"]
        }

        return featureList.isEmpty
            ? "Target: \(targetTemp)°C"
            : "Target: \(targetTemp)°C • \(featureList.joined(separator: ", "))"
    }

    func performAction(action: String) {
        print("Performing \(action)")
        self.buttonsDisabled = true

        var steeringWheelHeat = false
        var seatFL = false
        var seatFR = false
        var seatRL = false
        var seatRR = false
        var defrost = false

        if action == "start" {
            if let weather = locationManager.weather {
                let temp = weather.currentWeather.temperature.converted(to: .celsius).value
                if temp < 0 {
                    steeringWheelHeat = true
                    seatFL = true
                    seatFR = true
                    seatRL = true
                    seatRR = true
                    defrost = true
                }
            }
        }

        car.performAction(
            action: action,
            steeringWheel: steeringWheelHeat,
            seatFL: seatFL,
            seatFR: seatFR,
            seatRL: seatRL,
            seatRR: seatRR,
            defrost: defrost
        )

        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                if action != "resync" {
                    car.performAction(action: "resync")
                }
                car.apiResponse = apiResponse
                car.fetchCarDetails()
            }
        }

        Timer.scheduledTimer(withTimeInterval: 90.0, repeats: false) { _ in
            Task { @MainActor in
                if action != "resync" {
                    car.performAction(action: "resync")
                }
                car.apiResponse = apiResponse
                car.fetchCarDetails()
                self.buttonsDisabled = false
            }
        }
    }
}

#Preview {
    CarDetailView(car: MockData.createCar(), locationManager: LocationManager())
}

struct CarClimateView: View {
    var car: Car
    @ObservedObject var locationManager: LocationManager
    @Environment(\.presentationMode) var presentationMode

    @State private var steeringWheelHeat: Bool = false
    @State private var seatFL: Bool = false
    @State private var seatFR: Bool = false
    @State private var seatRL: Bool = false
    @State private var seatRR: Bool = false
    @State private var defrost: Bool = false
    @State private var temperature: Double = 21.0
    @State private var buttonsDisabled: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Climate Options")) {
                Toggle("Defrost", isOn: $defrost)
                Toggle("Steering Wheel Heat", isOn: $steeringWheelHeat)
                HStack {
                    Text("Temperature")
                    Spacer()
                    Stepper("\(Int(temperature))°C", value: $temperature, in: 16...28, step: 0.5)
                }
            }

            Section(header: Text("Seat Heating (Level 1)")) {
                HStack {
                    Toggle("Driver", isOn: $seatFL)
                    Toggle("Pass.", isOn: $seatFR)
                }
                HStack {
                    Toggle("Rear L", isOn: $seatRL)
                    Toggle("Rear R", isOn: $seatRR)
                }
            }

            Section {
                Button("Start Climate") {
                    performAction(action: "start")
                }
                .disabled(buttonsDisabled)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Theme.Colors.accent)
                .foregroundColor(.white)
            }
        }
        .navigationTitle("Climate Control")
        .onAppear {
            if let weather = locationManager.weather {
                let temp = weather.currentWeather.temperature.converted(to: .celsius).value
                if temp < 0 {
                    steeringWheelHeat = true
                    seatFL = true
                    seatFR = true
                    seatRL = true
                    seatRR = true
                    defrost = true
                }

                if temp < 25 {
                    temperature = 21.0
                } else {
                    temperature = 24.0
                }
            }
        }
        .scrollContentBackground(.hidden)
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
    }

    func performAction(action: String) {
        self.buttonsDisabled = true
        car.performAction(
            action: action,
            steeringWheel: steeringWheelHeat,
            seatFL: seatFL,
            seatFR: seatFR,
            seatRL: seatRL,
            seatRR: seatRR,
            defrost: defrost,
            temperature: Int(temperature)
        )

        // Go back after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            self.presentationMode.wrappedValue.dismiss()
        }

        // Resync logic is handled in CarDetailView listeners usually,
        // but here we just fire the action.
        // We might want to trigger the resync polling here too if we want to be safe,
        // but since we dismiss, the parent view's poll might pick it up if it was active,
        // or we just rely on the server delay.

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            car.performAction(action: "resync")
        }
    }
}
