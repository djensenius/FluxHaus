//
//  Weather.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import SwiftUI

struct Weather: View {
    @ObservedObject var lm = LocationManager.init()

    var body: some View {
        VStack {
            Text("The Weather!")
            Text(lm.weather.current?.weather[0].weatherDescription ?? "Fetching weather")
        }
    }
}

struct Weather_Previews: PreviewProvider {
    static var previews: some View {
        Weather()
    }
}
