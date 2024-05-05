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
            Text(robot.name)
                .font(.title)
                .padding([.top, .bottom])
            VStack(alignment: .leading) {
                Text("Data Updated \(getCarTime(strDate: robot.timestamp))")
                Text("Battery: \(String(describing: robot.batteryLevel))%")
                if robot.charging == true {
                    Text("Charging")
                } else if robot.running == true {
                    Text("Running since \(getCarTime(strDate: robot.timestamp))")
                } else if robot.docking == true {
                    Text("Docking")
                } else if robot.paused == true {
                    Text("Paused")
                } else {
                    Text("Idle")
                }
            }.padding(.bottom)

            HStack {
                if robot.running == true {
                    Button("Stop", action: { performAction(action: "stop") })
                        .disabled(self.buttonsDisabled)
                } else {
                    Button("Start", action: { performAction(action: "start") })
                        .disabled(self.buttonsDisabled)
                    Button("Deep Clean", action: { performAction(action: "deepClean") })
                        .disabled(self.buttonsDisabled)
                }
            }.padding()

            if self.buttonsDisabled {
                Text("It takes about 90 seconds for requests to finish, feel free to dismiss this window.")
                    .font(.caption)
                    .padding()
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
        robots.performAction(action: action, robot: robot.name)

        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) {_ in
            robots.fetchRobots()
        }
    }
}

/*
#Preview {
    CarDetailView()
}
*/
