//
//  RingView.swift
//  FluxHaus
//
//  Created by David Jensenius on 2024-03-30.
//

import HealthKitUI
import SwiftUI

struct RingView: UIViewRepresentable {
    typealias UIViewType = HKActivityRingView

    private let activitySummary: HKActivitySummary
    init(activitySummary: HKActivitySummary) {
        self.activitySummary = activitySummary
    }

    func makeUIView(context: Context) -> HKActivityRingView {
        let view = HKActivityRingView()
        view.activitySummary = activitySummary
        view.backgroundColor = UIColor.clear

        return view
    }

    func updateUIView(_ uiView: HKActivityRingView, context: Context) {
        uiView.activitySummary = activitySummary
    }
}
