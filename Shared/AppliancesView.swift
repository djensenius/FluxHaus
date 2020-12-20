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

    private var gridItemLayout = [GridItem(.flexible())]

    private let theAppliances = [ (name: "HomeConnect", index: 0), (name: "Miele", index: 0), (name: "Miele", index: 1) ]

    var body: some View {
        ScrollView {
                LazyVGrid(columns: gridItemLayout, spacing: 5) {
                    ForEach((0..<3), id: \.self) { i in
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color(UIColor.systemGray6))
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(getApplianceName(type: theAppliances[i].name, index: theAppliances[i].index))
                                            .font(.title2)
                                            .padding(.leading)
                                        Spacer()
                                    }
                                    Text(getProgram(type: theAppliances[i].name, index: theAppliances[i].index))
                                        .font(.subheadline)
                                        .padding(.leading)
                                }
                                Text(getTimeRemaining(type: theAppliances[i].name, index: theAppliances[i].index))
                                    .font(.largeTitle)
                                    .padding()
                            }
                        }
                    }.padding(.horizontal)
                }
        }.onAppear(perform: {let _ = self.updateTimer; fetchAppliances()})
    }

    func getApplianceName(type: String, index: Int) -> String {
        if (type == "HomeConnect") {
            if (hc.appliance.name == "") {
                return "🍽 Dishwasher"
            }
            return "🍽 \(hc.appliance.name)"
        }

        if (type == "Miele") {
            if (miele.appliances.count > index) {
                var emoji = "👖"
                if (miele.appliances[index].name == "Washer") {
                    emoji = "👕"
                }
                return "\(emoji) \(miele.appliances[index].name)"
            }
        }
        return "Fetching"
    }

    func getProgram(type: String, index: Int) -> String {
        if (type == "Miele") {
            if (miele.appliances.count > index && miele.appliances[index].programName != "") {
                return "\(miele.appliances[index].step) (\(miele.appliances[index].programName))"
            } else if (miele.appliances.count > index)  {
                return "\(miele.appliances[index].step)"
            }
        }
        return ""
    }

    func getTimeRemaining(type: String, index: Int) -> String {
        if (type == "Miele" && miele.appliances.count > index) {
            return "\(miele.appliances[index].timeRemaining)m"
        }
        return "Off"
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true,
                             block: {_ in
                                fetchAppliances()
                             })
    }

    func fetchAppliances() -> Void {
        hc.authorize()
        FluxHausConsts.mieleAppliances.forEach { (appliance) in
            miele.fetchAppliance(appliance: appliance)
        }
    }
}



struct Appliances_Previews: PreviewProvider {
    static var previews: some View {
        Appliances()
    }
}
