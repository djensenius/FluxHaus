//
//  Appliances.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI

struct Appliances: View {
    var fluxHausConsts: FluxHausConsts
    @ObservedObject var hconn: HomeConnect
    @ObservedObject var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car

    @State private var showCarModal: Bool = false
    @State private var showBroomBotModal: Bool = false
    @State private var showMopBotModal: Bool = false
    @State private var showApplianceModal: [String: Bool] = [:]

    private let gridItemLayout = [GridItem(.flexible())]

    var originalAppliances = [
        (name: "HomeConnect", index: 0),
        (name: "Miele", index: 0),
        (name: "Miele", index: 1),
        (name: "BroomBot", index: 0),
        (name: "MopBot", index: 0),
        (name: "Car", index: 0),
        (name: "Battery", index: 0)
    ]

    @State var theAppliances: [(name: String, index: Int)] = []

    var body: some View {
        ScrollView {
                LazyVGrid(columns: gridItemLayout, spacing: 5) {
                    ForEach((0..<theAppliances.count), id: \.self) { app in
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
                                    .sheet(
                                        isPresented:
                                            binding(for: "\(theAppliances[app].name)-\(theAppliances[app].index)")
                                    ) {
                                        getSheet(
                                            type: theAppliances[app].name,
                                            index: theAppliances[app].index
                                        )
                                    }
                                }.onTapGesture {
                                    if theAppliances[app].name == "Car" {
                                        self.car.fetchCarDetails()
                                        self.showCarModal = true
                                    } else if theAppliances[app].name == "MopBot" {
                                        self.showMopBotModal = true
                                    } else if theAppliances[app].name == "BroomBot" {
                                        self.showBroomBotModal = true
                                    } else  if theAppliances[app].name != "Battery" {
                                        self.showApplianceModal[
                                            "\(theAppliances[app].name)-\(theAppliances[app].index)"
                                        ] = true
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
        .sheet(isPresented: self.$showBroomBotModal) {
            RobotDetailView(robot: robots.broomBot, robots: robots)
        }
        .sheet(isPresented: self.$showMopBotModal) {
            RobotDetailView(robot: robots.mopBot, robots: robots)
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
            return Binding(get: {
                return self.showApplianceModal[key] ?? false
            }, set: {
                self.showApplianceModal[key] = $0
            })
        }

    func getSheet(type: String, index: Int) -> ApplianceDetailView? {
        if type == "Miele" {
            return ApplianceDetailView(appliance: miele.appliances[index])
        } else if type == "HomeConnect" {
            return ApplianceDetailView(appliance: hconn.appliances[index])
        }
        return nil
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
           return getMopBotText()
        } else if type == "BroomBot" {
           return getBroomBotText()
        } else if type == "Battery" {
            if battery.state == .charging {
                return "Charging"
            } else if battery.state == .unknown {
                return "Battery state unknown"
            }
            return ""
        } else if type == "Car" {
            return carDetails(car: car)
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceValue(tAppliance: tAppliance, index: index)
        }
        return ""
    }

    func getMopBotText() -> String {
        var text = ""
        if robots.mopBot.running == true && robots.mopBot.timeStarted != nil {
            text = "Started \(getCarTime(strDate: robots.mopBot.timeStarted!)) "
        }
        if robots.mopBot.batteryLevel != nil && robots.mopBot.batteryLevel! < 100 {
            text += robots.mopBot.charging! ?
                "Charging (\(robots.mopBot.batteryLevel!)%)" : "Battery (\(robots.mopBot.batteryLevel!)%)"
        }
        return text
    }

    func getBroomBotText() -> String {
        var text = ""
        if robots.broomBot.running == true && robots.broomBot.timeStarted != nil {
            text = "Started \(getCarTime(strDate: robots.broomBot.timeStarted!)) "
        }
        if robots.broomBot.batteryLevel != nil && robots.broomBot.batteryLevel! < 100 {
            text += robots.broomBot.charging! ?
                "Charging (\(robots.broomBot.batteryLevel!)%)" : "Battery (\(robots.broomBot.batteryLevel!)%)"
        }
        return text
    }

    func tApplianceTimeRemaining(tAppliance: [Appliance], index: Int) -> String {
        if tAppliance.count == 0 { return "" }
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
            return "\(car.vehicle.batteryLevel)%"
        } else {
            tAppliance = hconn.appliances
        }

        if tAppliance.count > index {
            return tApplianceTimeRemaining(tAppliance: tAppliance, index: index)
        }
        return ""
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true,
                             block: {_ in
                                fetchAppliances()
                             })
    }

    func fetchAppliances() {
        robots.fetchRobots()
        car.performAction(action: "resync")
        hconn.authorize(boschAppliance: fluxHausConsts.boschAppliance)
        fluxHausConsts.mieleAppliances.forEach { (appliance) in
            miele.fetchAppliance(appliance: appliance)
        }
        print("No here")
        car.fetchCarDetails()
        self.sortAppliances()
    }

    func sortAppliances() {
        let appliances = originalAppliances

        var activeAppliances: [(name: String, index: Int)] = []
        var inactiveAppliances: [(name: String, index: Int)] = []

        appliances.forEach { appliance in
            let name = appliance.name
            let index = appliance.index
            switch name {
            case "Car", "Battery":
                activeAppliances.append(appliance)
            case "MopBot":
                if robots.mopBot.running != nil && (robots.mopBot.running == true || robots.mopBot.paused == true) {
                    activeAppliances.append(appliance)
                } else {
                    inactiveAppliances.append(appliance)
                }
            case "BroomBot":
                if robots.broomBot.running != nil &&
                    (robots.broomBot.running == true || robots.broomBot.paused == true) {
                    activeAppliances.append(appliance)
                } else {
                    inactiveAppliances.append(appliance)
                }
            case "Miele":
                let tAppliance = miele.appliances
                if tApplianceTimeRemaining(tAppliance: tAppliance, index: index) == "Off" {
                    inactiveAppliances.append(appliance)
                } else {
                    activeAppliances.append(appliance)
                }
            case "HomeConnect":
                let tAppliance = hconn.appliances
                if tApplianceTimeRemaining(tAppliance: tAppliance, index: index) == "Off" {
                    inactiveAppliances.append(appliance)
                } else {
                    activeAppliances.append(appliance)
                }
            default:
                break
            }
        }

        theAppliances = activeAppliances + inactiveAppliances
    }
}

/*
struct Appliances_Previews: PreviewProvider {
    static var previews: some View {
        Appliances()
    }
}
*/
