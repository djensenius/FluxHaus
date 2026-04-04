//
//  RobotsListView.swift
//  FluxHaus
//
//  Standalone robots view for iPad/VisionOS sidebar navigation.
//

import SwiftUI

struct RobotsListView: View {
    var robots: Robots
    @State private var showBroomBotSheet = false
    @State private var showMopBotSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                robotCard(
                    title: "BroomBot",
                    robot: robots.broomBot,
                    robotName: "broomBot",
                    icon: "fan",
                    showSheet: $showBroomBotSheet
                )
                robotCard(
                    title: "MopBot",
                    robot: robots.mopBot,
                    robotName: "mopBot",
                    icon: "humidifier.and.droplets",
                    showSheet: $showMopBotSheet
                )
            }
            .padding()
        }
        .sheet(isPresented: $showBroomBotSheet) {
            RobotDetailView(robot: robots.broomBot, robots: robots)
        }
        .sheet(isPresented: $showMopBotSheet) {
            RobotDetailView(robot: robots.mopBot, robots: robots)
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
    }

    private func robotCard(
        title: String,
        robot: Robot,
        robotName: String,
        icon: String,
        showSheet: Binding<Bool>
    ) -> some View {
        Button(action: { showSheet.wrappedValue = true }, label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(statusColor(robot))
                    Text(title)
                        .font(Theme.Fonts.headerLarge())
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    statusBadge(robot)
                }

                HStack(spacing: 16) {
                    if let battery = robot.batteryLevel {
                        Label(
                            "\(battery)%",
                            systemImage: batteryIcon(battery)
                        )
                        .foregroundColor(Theme.Colors.textPrimary)
                    }
                    if robot.binFull == true {
                        Label("Bin Full", systemImage: "trash.fill")
                            .foregroundColor(Theme.Colors.error)
                    }
                }
                .font(Theme.Fonts.bodyMedium)

                if robot.running == true, let started = robot.timeStarted {
                    Text("Started \(relativeTimeString(from: started))")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Text("Updated \(relativeTimeString(from: robot.timestamp))")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(12)
        })
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(_ robot: Robot) -> some View {
        if robot.running == true {
            Label("Running", systemImage: "play.circle.fill")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.accent)
        } else if robot.charging == true {
            Label("Charging", systemImage: "bolt.fill")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.success)
        } else if robot.docking == true {
            Label("Docking", systemImage: "house.fill")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        } else if robot.paused == true {
            Label("Paused", systemImage: "pause.circle.fill")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.warning)
        } else {
            Label("Idle", systemImage: "zzz")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func statusColor(_ robot: Robot) -> Color {
        if robot.running == true { return Theme.Colors.accent }
        if robot.charging == true { return Theme.Colors.success }
        if robot.binFull == true { return Theme.Colors.error }
        return Theme.Colors.textSecondary
    }

    private func batteryIcon(_ level: Int) -> String {
        if level > 75 { return "battery.100percent" }
        if level > 50 { return "battery.75percent" }
        if level > 25 { return "battery.50percent" }
        return "battery.25percent"
    }
}
