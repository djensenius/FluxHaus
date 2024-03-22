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
                    .font(.headline)
                    .padding()
                ForEach(alerts, id: \.summary) { alert in
                    VStack(alignment: .leading) {
                        if (alert.region != nil) {
                            Text("\(alert.severity.description.capitalized) alert for \(alert.region!)")
                        } else {
                            Text("\(alert.severity.description.capitalized)")
                        }
                        Text(alert.summary)
                        Link(destination: alert.detailsURL, label: {
                            Text(alert.source)
                        })
                    }
                    .padding()

                }
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Dismiss")
                }.padding()
            }
        }
    }
}
