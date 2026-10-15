//
//  FluxWidgetBundle.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

import WidgetKit
import SwiftUI

@main
struct FluxWidgetBundle: WidgetBundle {
    var body: some Widget {
        FluxWidget()
        FluxCarWidget()
        FluxScenesWidget()
        FluxHomeWidget()
        FluxWidgetOtherSmall()
        #if os(iOS) && !targetEnvironment(macCatalyst)
        FluxWidgetMultiLiveActivity()
        FluxWidgetLiveActivity()
        CleanbotControl()
        CarClimateControl()
        CarLockControl()
        SceneControl()
        #endif
    }
}
