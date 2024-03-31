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

    var body: some View {
        VStack {
            Text("Car")
                .font(.title)
                .padding([.top, .bottom])
            VStack(alignment: .leading) {
                Text("EV Data Updated \(getTime(strDate: car.vehicle.evStatusTimestamp))")
                Text("Battery: \(car.vehicle.batteryLevel)%, \(car.vehicle.distance) km")
                HStack {
                    if car.vehicle.pluggedIn {
                        Text("Plugged in")
                    } else {
                        Text("Unplugged")
                    }
                    if car.vehicle.batteryCharge {
                        Text("Charging")
                    } else {
                        Text("Not charging")
                    }
                }.padding(.bottom)
                Text("Other data updated \(getTime(strDate: car.vehicle.timestamp))")
                Text("Odometer: \(car.vehicle.odometer, specifier: "%.0f") km")
                HStack {
                    if car.vehicle.trunkOpen {
                        Text("Trunk open")
                    } else {
                        Text("Trunk closed")
                    }
                    if car.vehicle.hoodOpen {
                        Text("Hood open")
                    } else {
                        Text("Hood closed")
                    }
                }
            }.padding(.bottom)

            HStack {
                if car.vehicle.hvac {
                    Button("Turn Climate Off", action: { performAction(action: "stop") })
                        .disabled(self.buttonsDisabled)
                } else {
                    Button("Turn Climate On", action: { performAction(action: "start") })
                        .disabled(self.buttonsDisabled)
                }
                if car.vehicle.locked {
                    Button("Unlock", action: { performAction(action: "unlock") })
                        .disabled(self.buttonsDisabled)
                } else {
                    Button("Lock", action: { performAction(action: "lock") })
                        .disabled(self.buttonsDisabled)
                }
                Button("Resync data", action: { performAction(action: "rsync") })
                    .disabled(self.buttonsDisabled)
            }.padding()
            if self.buttonsDisabled {
                ProgressView()
            }
            Spacer()
            Button(action: {
                self.presentationMode.wrappedValue.dismiss()
            }, label: {
                Text("Dismiss")
            }).padding()
        }
    }

    func performAction(action: String) {
        print("Performing \(action)")
        self.buttonsDisabled = true
        car.performAction(action: action)

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) {_ in
            if action != "resync" {
                car.performAction(action: "resync")
            }
            car.fetchCarDetails()
        }

        Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) {_ in
            if action != "resync" {
                car.performAction(action: "resync")
            }
            car.fetchCarDetails()
            self.buttonsDisabled = false
        }
    }

    func getTime(strDate: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let date = dateFormatter.date(from: String(strDate))!.timeIntervalSince1970
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(
            for: Date.init(timeIntervalSince1970: TimeInterval(date)),
            relativeTo: Date()
        )
    }
}

/*
#Preview {
    CarDetailView()
}
*/
