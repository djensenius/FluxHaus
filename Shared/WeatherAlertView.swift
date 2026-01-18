//
//  WeatherAlertView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-27.
//

import SwiftUI
import WeatherKit

struct WeatherAlertView: View {
    @Environment(\.presentationMode) var presentationMode
    var alerts: [WeatherAlert]
    var body: some View {
        ScrollView {
            VStack {
                Text("Weather Alerts")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding()
                ForEach(alerts, id: \.summary) { alert in
                    VStack(alignment: .leading) {
                        if alert.region != nil {
                            Text("\(alert.severity.description.capitalized) alert for \(alert.region!)")
                                .font(Theme.Fonts.bodyLarge)
                                .foregroundColor(Theme.Colors.error)
                        } else {
                            Text("\(alert.severity.description.capitalized)")
                                .font(Theme.Fonts.bodyLarge)
                                .foregroundColor(Theme.Colors.error)
                        }
                        Text(alert.summary)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Link(destination: alert.detailsURL, label: {
                            Text(alert.source)
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        })
                    }
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(12)

                }
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }, label: {
                    Text("Dismiss")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundColor(Theme.Colors.accent)
                }).padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
        }
        .background(Theme.Colors.background)
    }
}

#Preview {
    WeatherAlertView(alerts: [WeatherAlert(
        summary: "Heat Warning",
        severity: .severe,
        source: "Environment Canada",
        detailsURL: URL(string: "https://weather.gc.ca")!
    )])
}
