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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
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
                    .padding(.top)

                    // Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            if appliance.timeRunning != 0 {
                                Label("Running for \(appliance.timeRunning) minutes", systemImage: "timer")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textPrimary)
                            }

                            if appliance.inUse == false {
                                Label("Off", systemImage: "power.circle")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            } else {
                                Label(
                                    "Finishing in \(appliance.timeRemaining) minutes at \(appliance.timeFinish)",
                                    systemImage: "hourglass"
                                )
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Text("Program: \(appliance.programName)")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)

                                Text("Step: \(appliance.step)")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)
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
