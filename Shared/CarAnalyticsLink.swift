//
//  CarAnalyticsLink.swift
//  FluxHaus
//

import SwiftUI

struct CarAnalyticsLink: View {
    var body: some View {
        NavigationLink(destination: CarAnalyticsView()) {
            HStack(spacing: Theme.Spacing.medium) {
                Image(systemName: "chart.xyaxis.line")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("Car Insights")
                        .font(Theme.Fonts.headerLarge())
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Charging, efficiency, weather impact, and long-term trends")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(visionOS)
            .glassBackgroundEffect(in: .rect(cornerRadius: Theme.cornerRadius))
            #else
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            #endif
        }
        .buttonStyle(.plain)
    }
}
