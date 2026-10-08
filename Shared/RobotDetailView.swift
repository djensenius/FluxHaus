//
//  CarDetailView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import SwiftUI

struct RobotDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    var robot: Robot
    var robots: Robots
    @State private var buttonsDisabled: Bool = false

    private var usesTabletopControlBase: Bool {
        #if os(iOS)
        AdaptiveLayout.usesTabletopControlBase(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    #if !os(macOS)
                    // Header
                    HStack {
                        Image(systemName: "robotic.vacuum.fill")
                            .deviceSymbolAnimation(
                                .variableColor,
                                isActive: robot.running == true || robot.paused == true
                            )
                        Text(robot.name ?? "Cleanbot")
                    }
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.top)
                    #endif

                    // Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Battery: \(robot.batteryLevel ?? 0)%")
                                .font(Theme.Fonts.bodyLarge)
                                .foregroundColor(Theme.Colors.textPrimary)

                            if robot.charging == true && robot.batteryLevel ?? 0 < 100 {
                                Label("Charging", systemImage: "bolt.fill")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.success)
                            } else if robot.running == true {
                                let startedTime = relativeTimeString(
                                    from: robot.timeStarted ?? robot.timestamp
                                )
                                Label(
                                    "Cleaning started \(startedTime)",
                                    systemImage: "fan.fill"
                                )
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.accent)
                            } else if robot.docking == true {
                                Label("Docking", systemImage: "house.fill")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            } else if robot.paused == true {
                                Label("Paused", systemImage: "pause.circle.fill")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.warning)
                            } else {
                                Label("Idle", systemImage: "zzz")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Text("Data Updated \(relativeTimeString(from: robot.timestamp))")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if !os(visionOS)
                    .background(Theme.Colors.secondaryBackground)
                    #endif
                    .cornerRadius(12)

                    cleanStatsCard
                    baseStationCard
                    maintenanceCard
                    roomCleaningCard

                    if !usesTabletopControlBase {
                        robotControlsCard
                    }

                    if self.buttonsDisabled {
                        VStack {
                            Text("It takes about 30 seconds for requests to finish, feel free to dismiss this window.")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding()
                            ProgressView()
                        }
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if usesTabletopControlBase {
                    robotControlsCard
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .background(.bar)
                }
            }
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            #endif
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
        .fluxDeviceAnnotation(.cleanBot)
    }

    private var cleanStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Clean")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            if let progress = robot.progressPercent {
                ProgressView(value: progress, total: 100)
                detailLine("Progress", "\(Int(progress.rounded()))%", icon: "gauge.with.dots.needle.67percent")
            }
            if let remaining = robot.estimatedRemainingMinutes {
                detailLine("Time Left", "~\(Int(remaining.rounded())) min", icon: "timer")
            }
            if let elapsed = robot.elapsedMinutes {
                detailLine("Elapsed", "\(Int(elapsed.rounded())) min", icon: "clock")
            }
            if let area = robot.cleanedArea {
                detailLine("Cleaned", "\(Int(area.rounded())) m²", icon: "ruler")
            }
            if let room = robot.currentRoom {
                detailLine("Current Room", room, icon: "house")
            }
            if let mode = robot.cleaningMode {
                detailLine("Mode", mode.capitalized, icon: "sparkles")
            }
            if let suction = robot.suctionLevel {
                detailLine("Suction", suction.capitalized, icon: "fan")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
    }

    private var baseStationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Base Station")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            detailLine("Clean Water", displayStatus(robot.cleanWaterTankStatus), icon: "drop.fill")
            detailLine("Dirty Water", displayStatus(robot.dirtyWaterTankStatus), icon: "drop.triangle.fill")
            detailLine("Dust Bag", displayStatus(robot.dustBagStatus), icon: "trash.fill")
            detailLine("Detergent", displayStatus(robot.detergentStatus), icon: "drop")
            detailLine("Low Water", displayStatus(robot.lowWaterWarning), icon: "exclamationmark.triangle")
            detailLine("Auto Empty", displayStatus(robot.autoEmptyStatus), icon: "trash")
            detailLine("Drainage", displayStatus(robot.drainageStatus), icon: "water.waves")
            detailLine("Self-Wash Base", displayStatus(robot.selfWashBaseStatus), icon: "water.waves")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            detailLine("Main Brush", percentText(robot.maintenance?.mainBrushPercent), icon: "paintbrush.fill")
            detailLine("Side Brush", percentText(robot.maintenance?.sideBrushPercent), icon: "pinwheel")
            detailLine(
                "Filter",
                percentText(robot.maintenance?.filterPercent),
                icon: "line.3.horizontal.decrease.circle"
            )
            detailLine("Sensors", percentText(robot.maintenance?.sensorPercent), icon: "dot.radiowaves.left.and.right")
            detailLine("Wheels", percentText(robot.maintenance?.wheelPercent), icon: "circle.circle.fill")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
    }

    private var roomCleaningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Room Cleaning")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)
            if let rooms = robot.rooms, !rooms.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(rooms) { room in
                        Button(action: { performRoomClean(room) }, label: {
                            Label(room.name, systemImage: "house")
                        })
                        .buttonStyle(.bordered)
                        .disabled(buttonsDisabled)
                    }
                }
            } else {
                Text("Room list unavailable")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
    }

    @ViewBuilder
    private func detailLine(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private func displayStatus(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var robotControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.textPrimary)

            #if os(macOS) || os(visionOS)
            HStack(spacing: 8) {
                if robot.running == true {
                    Button(action: { performAction(action: "stop") }, label: {
                        Label("Stop", systemImage: "stop.fill")
                    })
                    .tint(Theme.Colors.error)
                } else {
                    Button(action: { performAction(action: "start") }, label: {
                        Label("Start", systemImage: "play.fill")
                    })
                    .tint(Theme.Colors.accent)
                }
            }
            .buttonStyle(.bordered)
            .disabled(buttonsDisabled)
            #else
            VStack(spacing: 12) {
                if robot.running == true {
                    Button(action: { performAction(action: "stop") }, label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            #if os(visionOS)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            #else
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(8)
                            #endif
                            .foregroundColor(Theme.Colors.textPrimary)
                    })
                    .disabled(self.buttonsDisabled)
                } else {
                    Button(action: { performAction(action: "start") }, label: {
                        Label("Start Cleaning", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Colors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    })
                    .disabled(self.buttonsDisabled)
                }
            }
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(visionOS)
        .background(Theme.Colors.secondaryBackground)
        #endif
        .cornerRadius(12)
    }

    func performAction(action: String) {
        print("Performing \(action)")
        self.buttonsDisabled = true
        robots.performAction(action: action, robot: robot.name ?? "Cleanbot")
        finishPendingAction()
    }

    func performRoomClean(_ room: RobotRoom) {
        self.buttonsDisabled = true
        robots.cleanRoom(room)
        finishPendingAction()
    }

    private func finishPendingAction() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                robots.fetchRobots()
                self.buttonsDisabled = false
            }
        }
    }
}

#if DEBUG
#Preview {
    RobotDetailView(robot: MockData.loginResponse.cleanbot, robots: MockData.createRobots())
}
#endif
