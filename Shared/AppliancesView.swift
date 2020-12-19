//
//  Appliances.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI

struct Appliances: View {
    @ObservedObject var hc = HomeConnect.init()
    @ObservedObject var miele = Miele.init()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.green)
                .frame(width: 150, height: 150)

            VStack {
                Image(systemName: "cloud.heavyrain.fill")
                Text(hc.appliance.name)
                    .onAppear(perform: {let _ = self.updateTimer})
            }
        }
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true,
                             block: {_ in
                                fetchAppliances()
                                // self.washingMachine = HomeConnect.appliance
                             })
    }
}

func fetchAppliances() -> Void {
    print("Looping")
    FluxHausConsts.mieleAppliances.forEach { (appliance) in
        miele.fetchAppliance(appliance: appliance)
        /*
        Appliance.fetchMiele(appliance: appliance) { (app: Appliance) in
            print("Hi \(app)")
        }
        */
    }
    hc.authorize()
}

struct Appliances_Previews: PreviewProvider {
    static var previews: some View {
        Appliances()
    }
}
