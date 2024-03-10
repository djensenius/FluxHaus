//
//  HomeKitView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-20.
//

import SwiftUI

struct HomeKitView: View {
    var favouriteHomeKit: [String]
    
    @ObservedObject var home = HomeKitIntegration()
    private let gridItemLayout = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: gridItemLayout, spacing: 1) {
                ForEach(0..<home.favourites.count, id: \.self) { i in
                    if (favouriteHomeKit.contains(home.favourites[i].name)) {
                        Button(action: {
                            home.primaryHome?.executeActionSet(home.favourites[i].hkSet, completionHandler: { (_) in
                                print("Executed")
                            })
                            print("Tapped \(home.favourites[i].name)")
                        }) {
                            HStack {
                                Text(home.favourites[i].name)
                                    .font(.subheadline)
                                    .frame(width: 100)
                            }
                            .padding()
                            .foregroundColor(getButtonForegroundColor(favourite: home.favourites[i]))
                            .background(getButtonBackgroundColor(favourite: home.favourites[i]))
                            .cornerRadius(20)
                            .frame(width: 150, height: 70, alignment: .center)
                        }.frame(minWidth: 150, idealWidth: 150, maxWidth: .infinity, minHeight: 0, idealHeight: 100, maxHeight: .infinity, alignment: .center)
                    }
                }
            }.onAppear(perform: {
                home.startHome()
                let _ = self.updateTimer
            })
        }
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true,
                             block: {_ in
                                home.startHome()
                             })
    }
    
    func getButtonForegroundColor(favourite: HomeKitFavourite) -> Color {
        if (!favourite.isActive) {
            return Color(UIColor.systemGray)
        } else {
            return Color(UIColor.systemGray6)
        }
    }

    func getButtonBackgroundColor(favourite: HomeKitFavourite) -> Color {
        if (!favourite.isActive) {
            return Color(UIColor.systemFill)
        } else {
            return Color(UIColor.systemGray2)
        }
    }
}

/*
struct HomeKitView_Previews: PreviewProvider {
    static var previews: some View {
        HomeKitView()
    }
}
*/
