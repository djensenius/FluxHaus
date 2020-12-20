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
        HStack {
            if shouldShow(type: "HomeConnect", index: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(getApplianceColor(type: "HomeConnect", index: 0))
                        .frame(width: 90, height: 90)

                    VStack {
                        Text(getApplianceName(type: "HomeConnect", index: 0))
                            .font(.caption)
                        Text(hc.appliance.timeFinish)
                            .font(.subheadline)
                    }
                }
            }

            if shouldShow(type: "Miele", index: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.green)
                        .frame(width: 90, height: 90)

                    VStack {
                        Text(getApplianceName(type: "Miele", index: 0))
                            .font(.callout)
                        Text(getTimeRemaining(type: "Miele", index: 0))
                            .font(.caption2)
                        Text(getProgram(type: "Miele", index: 0))
                            .font(.caption2)
                    }
                }
            }

            if shouldShow(type: "Miele", index: 1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.green)
                        .frame(width: 90, height: 90)

                    VStack {
                        Text(getApplianceName(type: "Miele", index: 1))
                            .font(.callout)
                        Text(getTimeRemaining(type: "Miele", index: 1))
                            .font(.caption2)
                        Text(getProgram(type: "Miele", index: 1))
                            .font(.caption2)
                    }
                }
            }
        }
        .onAppear(perform: {let _ = self.updateTimer; fetchAppliances()})
    }

    func getApplianceColor(type: String, index: Int) -> Color {
        if (type == "HomeConnect") {
            if (hc.appliance.inUse == true) {
                return Color.green
            }
        }

        return Color.gray
    }

    func shouldShow(type: String, index: Int) -> Bool {
        if (type == "HomeConnect") {
            if hc.appliance.inUse == true {
                return true
            }
        } else if (type == "Miele") {
            if (miele.appliances.count > index) {
                if miele.appliances[index].inUse == true {
                    return true
                }
            }
        }
        return false
    }

    func getApplianceName(type: String, index: Int) -> String {
        if (type == "HomeConnect") {
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
        return ""
    }

    func getProgram(type: String, index: Int) -> String {
        if (type == "Miele") {
            return "\(miele.appliances[index].step) (\(miele.appliances[index].programName))"
        }
        return ""
    }

    func getTimeRemaining(type: String, index: Int) -> String {
        if (type == "Miele") {
            return "Finish: \(miele.appliances[index].timeFinish)\nIn \(miele.appliances[index].timeRemaining) minutes"
        }
        return ""
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true,
                             block: {_ in
                                fetchAppliances()
                                // self.washingMachine = HomeConnect.appliance
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
