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
    @ObservedObject var apiResponse: Api

    var robots: Robots
    var battery: Battery
    var car: Car

    @State private var showCarModal: Bool = false
    @State private var showBroomBotModal: Bool = false
    @State private var showMopBotModal: Bool = false
    @State private var showApplianceModal: [String: Bool] = [:]
    @State var theAppliances: [(name: String, index: Int)] = []

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
                                                .font(Theme.Fonts.headerLarge())
                                                .foregroundColor(getIconColor(
                                                    type: theAppliances[app].name,
                                                    index: theAppliances[app].index
                                                ))
                                                .padding(.leading)
                                                Text(
                                                    getApplianceName(
                                                        type: theAppliances[app].name,
                                                        index: theAppliances[app].index
                                                    )
                                                )
                                                .font(Theme.Fonts.headerLarge())
                                                .foregroundColor(Theme.Colors.textPrimary)
                                                Spacer()
                                            }
                                            Text(
                                                getProgram(
                                                    type: theAppliances[app].name,
                                                    index: theAppliances[app].index
                                                )
                                            )
                                            .font(Theme.Fonts.caption)
                                            .foregroundColor(Theme.Colors.textSecondary)
                                            .padding(.leading)
                                        }
                                        Text(
                                            getTimeRemaining(
                                                type: theAppliances[app].name,
                                                index: theAppliances[app].index
                                            )
                                        )
                                        .font(Theme.Fonts.headerXL())
                                        .foregroundColor(Theme.Colors.secondary)
                                        .padding()
                                    }
                                    #if os(visionOS)
                                    .glassBackgroundEffect(in: .rect(cornerRadius: 12))
                                    #else
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(12)
                                    #endif
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
                                        self.car.apiResponse = self.apiResponse
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

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true,
                             block: { _ in
                                Task { @MainActor in
                                    fetchAppliances()
                                }
                             })
    }

    func fetchAppliances() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            robots.setApiResponse(apiResponse: apiResponse)
            hconn.setApiResponse(apiResponse: self.apiResponse)
            miele.setApiResponse(apiResponse: self.apiResponse)
            car.setApiResponse(apiResponse: apiResponse)
            self.sortAppliances()
            return
        }
        #endif

        if WhereWeAre.getPassword() != nil {
            robots.setApiResponse(apiResponse: apiResponse)
            hconn.setApiResponse(apiResponse: self.apiResponse)
            miele.setApiResponse(apiResponse: self.apiResponse)
            car.setApiResponse(apiResponse: apiResponse)
            self.sortAppliances()
        }
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

struct Appliances_Previews: PreviewProvider {
    static var previews: some View {
        AppliancesPreviewWrapper()
    }
}

struct AppliancesPreviewWrapper: View {
    let robots = MockData.createRobots()
    let hconn = MockData.createHomeConnect()
    let miele = MockData.createMiele()
    let car = MockData.createCar()
    let battery = MockData.createBattery()
    let apiResponse = MockData.createApi()

    init() {
        // Ensure data is populated for the preview
        robots.setApiResponse(apiResponse: apiResponse)
        hconn.setApiResponse(apiResponse: apiResponse)
        miele.setApiResponse(apiResponse: apiResponse)
        car.setApiResponse(apiResponse: apiResponse)
    }

    var body: some View {
        Appliances(
            fluxHausConsts: {
                let config = FluxHausConsts()
                config.setConfig(config: FluxHausConfig(favouriteHomeKit: ["Light 1", "Light 2"]))
                return config
            }(),
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots,
            battery: battery,
            car: car
        )
    }
}
