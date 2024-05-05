//
//  CarDetailView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import SwiftUI

struct ApplianceDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    var appliance: Appliance
    @State private var buttonsDisabled: Bool = false

    var body: some View {
        VStack {
            HStack {
                if appliance.name == "MopBot" {
                    Image(systemName: "humidifier.and.droplets")
                } else {
                    Image(systemName: "fan")
                }
                Text(appliance.name)
            }
                .font(.title)
                .padding([.top, .bottom])

            VStack(alignment: .leading) {
                if appliance.timeRunning != 0 {
                    Text("Running for \(appliance.timeRunning) minutes")
                }
                if appliance.inUse == false {
                    Text("Off")
                } else {
                    Text("Finishing in \(appliance.timeRemaining) minutes at \(appliance.timeFinish)")
                    Text("Program: \(appliance.programName)")
                    Text("Step: \(appliance.step)")
                }
            }.padding(.bottom)

            Spacer()
            Button(action: {
                self.presentationMode.wrappedValue.dismiss()
            }, label: {
                Text("Dismiss")
            }).padding()
        }
    }
}
