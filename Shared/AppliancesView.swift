//
//  Appliances.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI

struct Appliance {
    let name: String
    let timeRunning: Int
    let timeRemaining: Int
    let timeFinish: String
    let step: String
    let programName: String
    let inUse: Bool
}

struct Appliances: View {
    var fluxHausConsts: FluxHausConsts
    @ObservedObject var hconn: HomeConnect
    @ObservedObject var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car

    @State private var showCarModal: Bool = false

    private let gridItemLayout = [GridItem(.flexible())]

    private let theAppliances = [
        (name: "HomeConnect", index: 0),
        (name: "Miele", index: 0),
        (name: "Miele", index: 1),
        (name: "BroomBot", index: 0),
        (name: "MopBot", index: 0),
        (name: "Car", index: 0),
        (name: "Battery", index: 0)
    ]

    var body: some View {
        ScrollView {
                LazyVGrid(columns: gridItemLayout, spacing: 5) {
                    ForEach((0..<6), id: \.self) { app in
                        if !(theAppliances[app].name == "Battery" && battery.model == .mac) {
                            if getApplianceName(
                                type: theAppliances[app].name,
                                index: theAppliances[app].index
                            ) != "Fetching" {
                                ZStack {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            HStack {
                                                Text(
                                                    getIcon(
                                                        type: theAppliances[app].name,
                                                        index: theAppliances[app].index
                                                    )
                                                )
                                                    .font(.title2)
                                                    .padding(.leading)
                                                Text(
                                                    getApplianceName(
                                                        type: theAppliances[app].name,
                                                        index: theAppliances[app].index
                                                    )
                                                )
                                                    .font(.title2)
                                                Spacer()
                                            }
                                            Text(
                                                getProgram(
                                                    type: theAppliances[app].name,
                                                    index: theAppliances[app].index
                                                )
                                            )
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading)
                                        }
                                        Text(
                                            getTimeRemaining(
                                                type: theAppliances[app].name,
                                                index: theAppliances[app].index
                                            )
                                        )
                                            .font(.title)
                                            .padding()
                                    }
                                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                                    .hoverEffect()
                                }.onTapGesture {
                                    if theAppliances[app].name == "Car" {
                                        self.showCarModal = true
                                    }
                                }
                            }
                        }
                    }.padding(.horizontal)
                }
        }
        .onAppear(perform: {_ = self.updateTimer; fetchAppliances()})
        .sheet(isPresented: self.$showCarModal) {
            CarDetailView(car: car)
        }
    }

    func getIcon(type: String, index: Int) -> Image {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            return Image(systemName: "humidifier.and.droplets")
        } else if type == "BroomBot" {
            return Image(systemName: "fan")
        } else if type == "Battery" {
            return getDeviceIcon(battery: battery)
        } else if type == "Car" {
            return Image(systemName: "car")
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            var emoji = Image(systemName: "dryer")
            if tAppliance[index].name == "Washing machine" {
                emoji = Image(systemName: "washer")
            } else if tAppliance[index].name == "Dishwasher" {
                emoji = Image(systemName: "dishwasher")
            }
            return emoji
        }
        return Image(systemName: "network")
    }

    func getApplianceName(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            return "MopBot"
        } else if type == "BroomBot" {
            return "BroomBot"
        } else if type == "Battery" {
            if battery.model == .iPad {
                return "iPad"
            } else if battery.model == .mac {
                return "Computer"
            } else if battery.model == .visionPro {
                return "Vision Pro"
            } else {
                return "Phone"
            }
        } else if type == "Car" {
            return "Car"
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            let text = "\(tAppliance[index].name)"
            return text
        }
        return "Fetching"
    }

    func tApplianceValue(tAppliance: [Appliance], index: Int) -> String {
        if tAppliance[index].inUse == false {
            return ""
        }
        if tAppliance.count > index && tAppliance[index].programName != "" {
            let step = tAppliance[index].step
            let programName = tAppliance[index].programName.trimmingCharacters(in: NSCharacterSet.whitespaces)
            return "\(step) (\(programName))"
        } else if tAppliance.count > index {
            return "\(tAppliance[index].step)"
        }
        return ""
    }

    func getProgram(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            if robots.mopBot.batteryLevel != nil && robots.mopBot.batteryLevel! < 100 {
                return robots.mopBot.charging! ?
                    "Charging (\(robots.mopBot.batteryLevel!)%)" : "Battery (\(robots.mopBot.batteryLevel!)%)"
            } else {
                return ""
            }
        } else if type == "BroomBot" {
            if robots.broomBot.batteryLevel != nil && robots.broomBot.batteryLevel! < 100 {
                return robots.broomBot.charging! ?
                    "Charging (\(robots.broomBot.batteryLevel!)%)" : "Battery (\(robots.broomBot.batteryLevel!)%)"
            } else {
                return ""
            }
        } else if type == "Battery" {
            if battery.state == .charging {
                return "Charging"
            } else if battery.state == .unknown {
                return "Unknown"
            }
            return ""
        } else if type == "Car" {
            return carDetails()
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceValue(tAppliance: tAppliance, index: index)
        }
        return ""
    }

    func tApplianceTimeRemaining(tAppliance: [Appliance], index: Int) -> String {
        if tAppliance[index].inUse == false {
            return "Off"
        }
        if tAppliance[index].timeRemaining > 60 {
            return tAppliance[index].timeFinish
        }
        return "\(tAppliance[index].timeRemaining)m"
    }

    func getTimeRemaining(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if type == "Miele" {
            tAppliance = miele.appliances
        } else if type == "MopBot" {
            if robots.mopBot.running != nil && (robots.mopBot.running == true || robots.mopBot.paused == true) {
                return "On"
            } else if robots.mopBot.running != nil && robots.mopBot.running == false {
                return "Off"
            } else {
                return "Lost"
            }
        } else if type == "BroomBot" {
            if robots.broomBot.running != nil && (robots.broomBot.running == true || robots.broomBot.paused == true) {
                return "On"
            } else if robots.broomBot.running != nil && robots.broomBot.running == false {
                return "Off"
            } else {
                return "Lost"
            }
        } else if type == "Battery" {
            return "\(battery.percent)%"
        } else if type == "Car" {
            return "\(car.vehicle.batteryLevel ?? 0)%"
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceTimeRemaining(tAppliance: tAppliance, index: index)
        }
        return ""
    }

    func carDetails() -> String {
        var text = ""
        if car.vehicle.engine { text += "Car on | " }

        if car.vehicle.hvac { text += "Climate on | " }

        text += "Range \(car.vehicle.distance ?? 0) km"
        return text
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true,
                             block: {_ in
                                fetchAppliances()
                             })
    }

    func fetchAppliances() {
        robots.fetchRobots()
        car.fetchCarDetails()
        hconn.authorize(boschAppliance: fluxHausConsts.boschAppliance)
        fluxHausConsts.mieleAppliances.forEach { (appliance) in
            miele.fetchAppliance(appliance: appliance)
        }
    }
}

/*
struct Appliances_Previews: PreviewProvider {
    static var previews: some View {
        Appliances()
    }
}
*/
