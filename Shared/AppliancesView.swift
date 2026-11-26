//
//  Appliances.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI

struct Appliances: View {
    var fluxHausConsts: FluxHausConsts
    var hconn: HomeConnect
    var miele: Miele
    var apiResponse: Api

    var robots: Robots
    var battery: Battery
    var car: Car
    var locationManager: LocationManager
    var airPurifier: AirPurifier
    /// The session's thermostat controller, whose accepted changes are newer than the last poll.
    var thermostat: Thermostat?
    /// Opens the Climate section. When set, an Indoor card joins the grid.
    var onOpenClimate: (() -> Void)?
    /// Whether the grid scrolls on its own; turn off when embedded in a scrolling dashboard.
    var scrolls = true

    @State private var showCarModal: Bool = false
    @State private var showScooterModal: Bool = false
    @State private var showCleanbotModal: Bool = false
    @State private var showAirPurifierModal: Bool = false
    @State private var showApplianceModal: [String: Bool] = [:]
    @State var theAppliances: [(name: String, index: Int)] = []

    private let gridItemLayout = [
        GridItem(.adaptive(minimum: AdaptiveLayout.cardMinimumWidth), spacing: 10)
    ]

    var originalAppliances = [
        (name: "HomeConnect", index: 0),
        (name: "Miele", index: 0),
        (name: "Miele", index: 1),
        (name: "Cleanbot", index: 0),
        (name: "Car", index: 0),
        (name: "Scooter", index: 0),
        (name: "Battery", index: 0),
        (name: "AirPurifier", index: 0)
    ]

    var body: some View {
        Group {
            if scrolls {
                ScrollView { grid }
            } else {
                grid
            }
        }
        .onAppear(perform: {_ = self.updateTimer; fetchAppliances()})
        .sheet(isPresented: self.$showCarModal) {
            CarDetailView(car: car, locationManager: locationManager, showsDismissButton: true)
        }
        .sheet(isPresented: self.$showScooterModal) {
            ScooterDetailView(
                scooter: {
                    let scooter = Scooter()
                    scooter.setApiResponse(apiResponse: apiResponse)
                    return scooter
                }()
            )
        }
        .sheet(isPresented: self.$showCleanbotModal) {
            RobotDetailView(robot: robots.cleanBot, robots: robots)
        }
        .sheet(isPresented: self.$showAirPurifierModal) {
            AirPurifierDetailView(purifier: airPurifier)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: gridItemLayout, spacing: 10) {
            ForEach((0..<theAppliances.count), id: \.self) { app in
                let name = theAppliances[app].name
                let index = theAppliances[app].index
                if !(name == "Battery" && battery.model == .mac),
                   getApplianceName(type: name, index: index) != "Fetching" {
                    if name == "Indoor" {
                        // Navigates rather than opening a sheet, so it's a real button for
                        // VoiceOver, Full Keyboard Access and pointer/gaze focus.
                        Button {
                            onOpenClimate?()
                        } label: {
                            card(type: name, index: index)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Climate")
                    } else {
                        ZStack {
                            card(type: name, index: index)
                                .sheet(isPresented: binding(for: "\(name)-\(index)")) {
                                    getSheet(type: name, index: index)
                                }
                        }
                        .onTapGesture { openSheet(type: name, index: index) }
                    }
                }
            }.padding(.horizontal)
        }
    }

    private func card(type: String, index: Int) -> some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    getIcon(type: type, index: index)
                        .font(Theme.Fonts.headerLarge())
                        .foregroundColor(getIconColor(type: type, index: index))
                        .padding(.leading)
                    Text(getApplianceName(type: type, index: index))
                        .font(Theme.Fonts.headerLarge())
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                }
                Text(getProgram(type: type, index: index))
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.leading)
            }
            Text(getTimeRemaining(type: type, index: index))
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
        #if !os(macOS)
        .hoverEffect()
        #endif
    }

    private func openSheet(type: String, index: Int) {
        switch type {
        case "Car":
            car.apiResponse = apiResponse
            car.fetchCarDetails()
            showCarModal = true
        case "Scooter":
            showScooterModal = true
        case "Cleanbot":
            showCleanbotModal = true
        case "AirPurifier":
            showAirPurifierModal = true
        case "Battery":
            break
        default:
            showApplianceModal["\(type)-\(index)"] = true
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
            airPurifier.setApiResponse(apiResponse: apiResponse)
            self.sortAppliances()
            return
        }
        #endif

        if WhereWeAre.getPassword() != nil || AuthManager.shared.isSignedIn {
            robots.setApiResponse(apiResponse: apiResponse)
            hconn.setApiResponse(apiResponse: self.apiResponse)
            miele.setApiResponse(apiResponse: self.apiResponse)
            car.setApiResponse(apiResponse: apiResponse)
            airPurifier.setApiResponse(apiResponse: apiResponse)
            self.sortAppliances()
        }
    }

    func sortAppliances() {
        var appliances = originalAppliances
        if onOpenClimate != nil {
            appliances.append((name: "Indoor", index: 0))
        }

        var activeAppliances: [(name: String, index: Int)] = []
        var inactiveAppliances: [(name: String, index: Int)] = []

        appliances.forEach { appliance in
            if isApplianceActive(name: appliance.name, index: appliance.index) {
                activeAppliances.append(appliance)
            } else {
                inactiveAppliances.append(appliance)
            }
        }

        theAppliances = activeAppliances + inactiveAppliances
    }

    private func isApplianceActive(name: String, index: Int) -> Bool {
        switch name {
        case "Car", "Scooter", "Battery":
            return true
        case "Cleanbot":
            return robots.cleanBot.running != nil && (robots.cleanBot.running == true || robots.cleanBot.paused == true)
        case "AirPurifier":
            return airPurifier.status.online && airPurifier.status.fanOn
        case "Indoor":
            return indoorSummary.isActive
        case "Miele":
            return tApplianceTimeRemaining(tAppliance: miele.appliances, index: index) != "Off"
        case "HomeConnect":
            return tApplianceTimeRemaining(tAppliance: hconn.appliances, index: index) != "Off"
        default:
            return false
        }
    }
}

#if DEBUG
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
    let locationManager = LocationManager() // Add this

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
                config.setConfig(config: FluxHausConfig(favouriteHomeKit: ["Light 1", "Light 2"], favouriteScenes: []))
                return config
            }(),
            hconn: hconn,
            miele: miele,
            apiResponse: apiResponse,
            robots: robots,
            battery: battery,
            car: car,
            locationManager: locationManager,
            airPurifier: MockData.createAirPurifier()
        )
    }
}
#endif
