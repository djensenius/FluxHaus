//
//  ScooterDetailView.swift
//  FluxHaus
//

import SwiftUI

struct ScooterDetailView: View {
    var scooter: Scooter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    #if !os(macOS)
                    HStack {
                        Image(systemName: "scooter")
                        Text("GT3 Pro")
                    }
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.top)
                    #endif

                    // Status Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(Theme.Fonts.headerLarge())
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            if let timestamp = scooter.summary.timestamp {
                                Text("Updated \(relativeTimeString(from: timestamp))")
                                    .font(Theme.Fonts.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            if let battery = scooter.summary.battery {
                                HStack(spacing: 4) {
                                    Text("Battery: \(battery)%")
                                    if let range = scooter.summary.estimatedRange {
                                        Text("·")
                                        Text(String(format: "%.0f km", range))
                                    }
                                }
                                .font(Theme.Fonts.bodyLarge)
                                .foregroundColor(Theme.Colors.textPrimary)
                            }

                            HStack(spacing: 16) {
                                Label(scooter.formattedOdometer, systemImage: "gauge.with.dots.needle.67percent")
                                    .foregroundColor(Theme.Colors.textPrimary)
                                if let cycles = scooter.summary.batteryCycles {
                                    Label("\(cycles) cycles", systemImage: "battery.100percent.circle")
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }
                            }
                            .font(Theme.Fonts.bodyMedium)

                            Label(
                                "Total ride time: \(scooter.formattedTotalRideTime)",
                                systemImage: "clock"
                            )
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textPrimary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(visionOS)
                    .glassBackgroundEffect()
                    #else
                    .background(Theme.Colors.secondaryBackground)
                    #endif
                    .cornerRadius(12)

                    // Last Ride Section
                    if let lastRide = scooter.summary.lastRide {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Last Ride")
                                .font(Theme.Fonts.headerLarge())
                                .foregroundColor(Theme.Colors.textPrimary)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(scooter.formattedLastRideDate)
                                    .font(Theme.Fonts.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)

                                HStack(spacing: 16) {
                                    Label(
                                        scooter.formattedLastRideDistance,
                                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                                    )
                                    .foregroundColor(Theme.Colors.textPrimary)

                                    if let maxSpeed = lastRide.maxSpeed {
                                        Label(
                                            String(format: "%.1f km/h", maxSpeed),
                                            systemImage: "speedometer"
                                        )
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    }
                                }
                                .font(Theme.Fonts.bodyMedium)

                                HStack(spacing: 16) {
                                    if let startBatt = lastRide.startBattery,
                                       let endBatt = lastRide.endBattery {
                                        Label(
                                            "\(startBatt)% → \(endBatt)%",
                                            systemImage: "battery.75percent"
                                        )
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    }

                                    Label(
                                        Scooter.gearName(lastRide.gearMode),
                                        systemImage: "gearshape"
                                    )
                                    .foregroundColor(Theme.Colors.textPrimary)
                                }
                                .font(Theme.Fonts.bodyMedium)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Theme.Colors.background)
            #if os(macOS)
            .navigationTitle("GT3 Pro")
            #endif
        }
    }
}
