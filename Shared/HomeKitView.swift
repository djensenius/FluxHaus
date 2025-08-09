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
    private let gridItemLayout = [GridItem(.flexible())]
    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: gridItemLayout, spacing: 1) {
                ForEach(0..<home.favourites.count, id: \.self) { fav in
                    if favouriteHomeKit.contains(home.favourites[fav].name) {
                        Button(action: {
                            home.primaryHome?.executeActionSet(home.favourites[fav].hkSet, completionHandler: { (_) in
                                print("Executed")
                            })
                            print("Tapped \(home.favourites[fav].name)")
                        }, label: {
                            HStack {
                                Text(home.favourites[fav].name)
                                    .font(.subheadline)
                                    .frame(width: 100)
                            }
                            .frame(width: 120, height: 50, alignment: .center)
                        })
                        .background(
                            getButtonBackgroundColor(favourite: home.favourites[fav]),
                            in: .rect(cornerRadius: 12)
                        )
                        #if os(visionOS)
                        .glassBackgroundEffect()
                        #endif
                        .padding(.leading)
                    }
                }
                #if targetEnvironment(simulator)
                Button(action: {}, label: {
                    HStack {
                        Text("Active")
                            .font(.subheadline)
                            .frame(width: 100)
                    }
                    .frame(width: 120, height: 50, alignment: .center)
                })
                .background(
                    .bar,
                    in: .rect(cornerRadius: 12)
                )
                #if os(visionOS)
                .glassBackgroundEffect()
                #endif
                .padding(.leading)
                Button(action: {}, label: {
                    HStack {
                        Text("Inactive")
                            .font(.subheadline)
                            .frame(width: 100)
                    }
                    .frame(width: 120, height: 50, alignment: .center)
                })
                .background(
                    .regularMaterial,
                    in: .rect(cornerRadius: 12)
                )
                #if os(visionOS)
                .glassBackgroundEffect()
                #endif
                .padding(.leading)
                #endif
            }.onAppear(perform: {
                home.startHome()
                _ = self.updateTimer
            })
        }
    }

    var updateTimer: Timer {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true,
                             block: { _ in
                                Task { @MainActor in
                                    home.startHome()
                                }
                             })
    }

    func getButtonBackgroundColor(favourite: HomeKitFavourite) -> Material {
        if !favourite.isActive {
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
