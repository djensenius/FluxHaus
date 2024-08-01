//
//  LiveActivityBundle.swift
//  LiveActivity
//
//  Created by David Jensenius on 2024-07-14.
//

import WidgetKit
import SwiftUI

@main
struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LiveActivity()
        #if canImport(ActivityKit)
        LiveActivityLiveActivity()
        #endif
    }
}
