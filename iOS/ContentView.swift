//
//  ContentView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-10.
//

import SwiftUI
import HealthKitUI

struct ContentView: View {
    var fluxHausConsts: FluxHausConsts
    var hconn: HomeConnect
    var miele: Miele
    var robots: Robots
    var battery: Battery
    var car: Car

    @State var authenticated = false
    @State var trigger = false
    var healthStore = HKHealthStore()
    let allTypes: Set = [
        HKQuantityType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning),
        HKObjectType.activitySummaryType()
    ]

    var body: some View {
        VStack {
            HStack {
                HStack {
                    // OK to read or write HealthKit data here.
                    if authenticated {
                        Text("HealthKit enabled")
                        RingView(activitySummary: HealthKit.HKActivitySummary())
                    }
                }
                // If HealthKit data is available, request authorization
                // when this view appears.
                .onAppear {
                    // Check that Health data is available on the device.
                    if HKHealthStore.isHealthDataAvailable() {
                        // Modifying the trigger initiates the health data
                        // access request.
                        trigger.toggle()
                    }
                }
                // Requests access to share and read HealthKit data types
                // when the trigger changes.
                /*
                .healthDataAccessRequest(store: healthStore,
                                         shareTypes: Set(),
                                         readTypes: allTypes,
                                         trigger: trigger) { result in
                    switch result {
                    case .success:
                        authenticated = true
                    case .failure(let error):
                        // Handle the error here.
                        print("FOUND ERROR")
                        fatalError("*** An error occurred while requesting authentication: \(error) ***")
                    }
                }
                 */
                VStack {
                    DateTimeView()
                    WeatherView()
                }
            }
            HomeKitView(favouriteHomeKit: fluxHausConsts.favouriteHomeKit)
            HStack {
                Text("Appliances")
                    .padding(.leading)
                Spacer()
            }
            Appliances(
                fluxHausConsts: fluxHausConsts,
                hconn: hconn,
                miele: miele,
                robots: robots,
                battery: battery,
                car: car
            )
            Spacer()
            Link(
                "Weather provided by  Weather",
                destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
            )
            .font(.footnote)
            .padding(.bottom)
        }
    }
}

/*
#Preview {
    ContentView()
}
*/
