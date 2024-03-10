//
//  Appliances.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-13.
//

import SwiftUI

struct Appliances: View {
    var fluxHausConsts: FluxHausConsts
    var hc: HomeConnect
    var miele: Miele
    
    // @ObservedObject var hc = HomeConnect.init()
    // @ObservedObject var miele = Miele.init()

    private let gridItemLayout = [GridItem(.flexible())]

    private let theAppliances = [ (name: "HomeConnect", index: 0), (name: "Miele", index: 0), (name: "Miele", index: 1) ]

    var body: some View {
        ScrollView {
                LazyVGrid(columns: gridItemLayout, spacing: 5) {
                    ForEach((0..<3), id: \.self) { i in
                        if (getApplianceName(type: theAppliances[i].name, index: theAppliances[i].index) != "Fetching") {
                            ZStack {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(Color(UIColor.systemGray6))
                                HStack {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(getIcon(type: theAppliances[i].name, index: theAppliances[i].index))
                                                .font(.title2)
                                                .padding(.leading)
                                            Text(getApplianceName(type: theAppliances[i].name, index: theAppliances[i].index))
                                                .font(.title2)
                                            Spacer()
                                        }
                                        Text(getProgram(type: theAppliances[i].name, index: theAppliances[i].index))
                                            .font(.subheadline)
                                            .padding(.leading)
                                    }
                                    Text(getTimeRemaining(type: theAppliances[i].name, index: theAppliances[i].index))
                                        .font(.title)
                                        .padding()
                                }
                            }
                        }
                    }.padding(.horizontal)
                }
        }.onAppear(perform: {let _ = self.updateTimer; fetchAppliances()})
    }
    
    func getIcon(type: String, index: Int) -> Image {
        var tAppliance: [Appliance]
        if (type == "Miele") {
            tAppliance = miele.appliances
        } else {
            tAppliance = hc.appliances
        }

        if (tAppliance.count > index) {
            var emoji = Image(systemName: "dryer")
            if (tAppliance[index].name == "Washing machine") {
                emoji = Image(systemName: "washer")
            } else if (tAppliance[index].name == "Dishwasher") {
                emoji = Image(systemName: "dishwasher")
            }
            return emoji
        }
        return Image(systemName: "network")
    }

    func getApplianceName(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if (type == "Miele") {
            tAppliance = miele.appliances
        } else {
            tAppliance = hc.appliances
        }

        if (tAppliance.count > index) {
            let text = "\(tAppliance[index].name)"
            return text
        }
        return "Fetching"
    }

    func getProgram(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if (type == "Miele") {
            tAppliance = miele.appliances
        } else {
            tAppliance = hc.appliances
        }

        if (tAppliance.count > index) {
            if (tAppliance[index].inUse == false) {
                return ""
            }
            if (tAppliance.count > index && tAppliance[index].programName != "") {
                return "\(tAppliance[index].step) (\(tAppliance[index].programName))"
            } else if (tAppliance.count > index)  {
                return "\(tAppliance[index].step)"
            }
        }
        return ""
    }

    func getTimeRemaining(type: String, index: Int) -> String {
        var tAppliance: [Appliance]
        if (type == "Miele") {
            tAppliance = miele.appliances
        } else {
            tAppliance = hc.appliances
        }
        if (tAppliance.count > index) {
            if (tAppliance[index].inUse == false) {
                return "Off"
            }
            if (tAppliance[index].timeRemaining > 60) {
                return tAppliance[index].timeFinish
            }
            return "\(tAppliance[index].timeRemaining)m"
        }
        return ""
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true,
                             block: {_ in
                                fetchAppliances()
                             })
    }

    func fetchAppliances() -> Void {
        hc.authorize(boschAppliance: fluxHausConsts.boschAppliance)
        fluxHausConsts.mieleAppliances.forEach { (appliance) in
            miele.fetchAppliance(appliance: appliance)
        }
    }
}


/*
struct Appliances_Previews: PreviewProvider {
    static var previews: some View {
        Appliances()
    }
}
*/
