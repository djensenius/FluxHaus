//
//  BackgroundView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2020-12-19.
//

import SwiftUI

struct BackgroundView: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.background)
            .edgesIgnoringSafeArea(.all)
    }
}

struct BackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        BackgroundView()
    }
}
