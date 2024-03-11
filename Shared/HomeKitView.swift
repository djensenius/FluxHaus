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
                            .frame(width: 120, height: 50, alignment: .center)
                        }
                        .background(
                            getButtonBackgroundColor(favourite: home.favourites[i]),
                            in: .rect(cornerRadius: 12)
                        )
                        .padding(.leading)
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

    func getButtonBackgroundColor(favourite: HomeKitFavourite) -> Material {
        if (!favourite.isActive) {
            return .bar
        } else {
            return .regularMaterial
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
