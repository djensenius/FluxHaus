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
        VStack {
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
                .padding([.top, .bottom])

            VStack(alignment: .leading) {
                Text("Battery: \(robot.batteryLevel ?? 0)%")
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundColor(Theme.Colors.textPrimary)
                if robot.charging == true && robot.batteryLevel ?? 0 < 100 {
                    Text("Charging")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.success)
                } else if robot.running == true {
                    Text("Cleaning started \(getCarTime(strDate: robot.timestamp))")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.accent)
                } else if robot.docking == true {
                    Text("Docking")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                } else if robot.paused == true {
                    Text("Paused")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.warning)
                } else {
                    Text("Idle")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Text("Data Updated \(getCarTime(strDate: robot.timestamp))")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }.padding(.bottom)

            VStack {
                if robot.running == true {
                    Button("Stop") { performAction(action: "stop") }
                    .buttonStyle(.fluxPrimary)
                    .disabled(self.buttonsDisabled)
                } else {
                    Button("Start Cleaning") { performAction(action: "start") }
                    .buttonStyle(.fluxPrimary)
                    .disabled(self.buttonsDisabled)
                    .padding(.bottom)

                    if robots.broomBot.running != true && robots.mopBot.running != true {
                        Button(action: { performAction(action: "deepClean") }, label: {
                            Text("Deep Clean (BroomBot + MopBot)")
                                .font(Theme.Fonts.bodyMedium)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Theme.Colors.secondaryBackground)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .cornerRadius(12)
                        })
                        .disabled(self.buttonsDisabled)
                    }
                }
            }.padding()

            if self.buttonsDisabled {
                Text("It takes about 30 seconds for requests to finish, feel free to dismiss this window.")
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
        robots.performAction(action: action, robot: robot.name!)

        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                robots.fetchRobots()
                self.buttonsDisabled = false
            }
        }
    }
}
