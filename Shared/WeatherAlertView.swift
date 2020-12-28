//
//  WeatherAlertView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-27.
//

import SwiftUI

struct WeatherAlertView: View {
    @Environment(\.presentationMode) var presentationMode
    var alerts: [Alert]
    var body: some View {
        VStack(alignment: .leading) {
            Text("Weather Alerts")
                .font(.headline)
                .padding()
            ForEach(alerts, id: \.description) { alert in
                VStack(alignment: .leading) {
                    Text("Start: \(getTime(time: alert.start))")
                    Text("End:   \(getTime(time: alert.end))")
                    Text(alert.description)
                }
                .padding()

            }
            Button(action: {
                self.presentationMode.wrappedValue.dismiss()
            }) {
                Text("Dismiss")
                    .padding()
            }
        }
    }

    func getTime(time: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(time))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a" //Set date style
        let localDate = formatter.string(from: date)
        return localDate
    }
}
