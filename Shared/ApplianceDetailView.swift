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
                    #if !os(macOS)
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
                    #endif

                    // Status Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            if appliance.timeRunning != 0 {
                                Label(
                                    "Running for \(formatDurationMinutes(appliance.timeRunning))",
                                    systemImage: "timer"
                                )
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textPrimary)
                            }

                            if appliance.inUse == false {
                                Label("Off", systemImage: "power.circle")
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            } else {
                                let remaining = formatDurationMinutes(appliance.timeRemaining)
                                Label(
                                    "Finishing in \(remaining) at \(appliance.timeFinish)",
                                    systemImage: "hourglass"
                                )
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                if !appliance.programName.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Label(appliance.programName.trimmingCharacters(in: .whitespaces),
                                          systemImage: "list.bullet")
                                        .font(Theme.Fonts.bodyMedium)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }

                                if !appliance.step.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Label(appliance.step.trimmingCharacters(in: .whitespaces),
                                          systemImage: "arrow.triangle.2.circlepath")
                                        .font(Theme.Fonts.bodyMedium)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if !os(visionOS)
                    .background(Theme.Colors.secondaryBackground)
                    #endif
                    .cornerRadius(12)
                }
                .padding()
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
