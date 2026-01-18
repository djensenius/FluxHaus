//
//  CarDetailView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import SwiftUI

struct RobotDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    var robot: Robot
    var robots: Robots
    @State private var buttonsDisabled: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        if robot.name! == "MopBot" {
                            Image(systemName: "humidifier.and.droplets")
                        } else {
                            Image(systemName: "fan")
                        }
                        Text(robot.name!)
                    }
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.top)

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
                                Label(
                                    "Cleaning started \(getCarTime(strDate: robot.timestamp))",
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

                            Text("Data Updated \(getCarTime(strDate: robot.timestamp))")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)

                    // Controls Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controls")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(spacing: 12) {
                            if robot.running == true {
                                Button(action: { performAction(action: "stop") }, label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Theme.Colors.secondaryBackground)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                        .cornerRadius(8)
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

                                if robots.broomBot.running != true && robots.mopBot.running != true {
                                    Button(action: { performAction(action: "deepClean") }, label: {
                                        Label("Deep Clean (BroomBot + MopBot)", systemImage: "sparkles")
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
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)

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

    func performAction(action: String) {
        print("Performing \(action)")
        self.buttonsDisabled = true
        robots.performAction(action: action, robot: robot.name!)

        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                robots.fetchRobots()
                self.buttonsDisabled = false
            }
        }
    }
}

#Preview {
    RobotDetailView(robot: MockData.loginResponse.broombot, robots: MockData.createRobots())
}
