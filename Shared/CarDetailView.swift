//
//  CarDetailView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import SwiftUI

struct CarDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    var car: Car
    @State private var buttonsDisabled: Bool = false
    @State var apiResponse: Api?

        var body: some View {
        VStack {
            HStack {
                Image(systemName: "car")
                Text("Car")
            }
                .font(Theme.Fonts.headerXL())
                .foregroundColor(Theme.Colors.textPrimary)
                .padding([.top, .bottom])

            VStack(alignment: .leading) {
                Text("EV Data Updated \(getCarTime(strDate: car.vehicle.evStatusTimestamp))")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("Battery: \(car.vehicle.batteryLevel)%, \(car.vehicle.distance) km")
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundColor(Theme.Colors.textPrimary)
                HStack {
                    if car.vehicle.pluggedIn {
                        Text("Plugged in")
                            .foregroundColor(Theme.Colors.success)
                    } else {
                        Text("Unplugged")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    if car.vehicle.batteryCharge {
                        Text("Charging")
                            .foregroundColor(Theme.Colors.success)
                    } else {
                        Text("Not charging")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .font(Theme.Fonts.bodyMedium)
                .padding(.bottom)
                Text("Other data updated \(getCarTime(strDate: car.vehicle.timestamp))")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("Odometer: \(car.vehicle.odometer, specifier: "%.0f") km")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
                HStack {
                    if car.vehicle.trunkOpen {
                        Text("Trunk open")
                            .foregroundColor(Theme.Colors.error)
                    } else {
                        Text("Trunk closed")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    if car.vehicle.hoodOpen {
                        Text("Hood open")
                            .foregroundColor(Theme.Colors.error)
                    } else {
                        Text("Hood closed")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                .font(Theme.Fonts.bodyMedium)
            }.padding(.bottom)

            VStack {
                if car.vehicle.hvac {
                    Button("Turn Climate Off") { performAction(action: "stop") }
                    .buttonStyle(.fluxPrimary)
                    .disabled(self.buttonsDisabled)
                } else {
                    Button("Turn Climate On") { performAction(action: "start") }
                    .buttonStyle(.fluxPrimary)
                    .disabled(self.buttonsDisabled)
                }
                if car.vehicle.locked {
                    Button("Unlock") { performAction(action: "unlock") }
                    .buttonStyle(.fluxPrimary)
                    .disabled(self.buttonsDisabled)
                } else {
                    Button("Lock") { performAction(action: "lock") }
                    .buttonStyle(.fluxPrimary)
                    .disabled(self.buttonsDisabled)
                }
                Button("Resync data") { performAction(action: "rsync") }
                .buttonStyle(.fluxPrimary)
                .disabled(self.buttonsDisabled)
            }.padding()
            if self.buttonsDisabled {
                Text("It takes about 90 seconds for requests to finish, feel free to dismiss this window.")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding()
                ProgressView()
            }
            Spacer()
            Button(action: {
                self.presentationMode.wrappedValue.dismiss()
            }, label: {
                Text("Dismiss")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.accent)
            }).padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
    }

    func performAction(action: String) {
        print("Performing \(action)")
        self.buttonsDisabled = true
        car.performAction(action: action)

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

/*
#Preview {
    CarDetailView()
}
*/
