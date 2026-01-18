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
                if appliance.name == "Washing machine" {
                   Image(systemName: "washer")
                } else if appliance.name == "Dishwasher" {
                    Image(systemName: "dishwasher")
                } else {
                    Image(systemName: "dryer")
                }
                Text(appliance.name)
            }
                .font(Theme.Fonts.headerXL())
                .foregroundColor(Theme.Colors.textPrimary)
                .padding([.top, .bottom])

            VStack(alignment: .leading) {
                if appliance.timeRunning != 0 {
                    Text("Running for \(appliance.timeRunning) minutes")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                if appliance.inUse == false {
                    Text("Off")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                } else {
                    Text("Finishing in \(appliance.timeRemaining) minutes at \(appliance.timeFinish)")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Program: \(appliance.programName)")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Text("Step: \(appliance.step)")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }.padding(.bottom)

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
}

#Preview {
    ApplianceDetailView(appliance: Appliance(
        name: "Washer",
        timeRunning: 45,
        timeRemaining: 15,
        timeFinish: "12:00 PM",
        step: "Rinse",
        programName: "Cotton 60",
        inUse: true
    ))
}
