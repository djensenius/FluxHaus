//
//  FluxWidgetLiveActivityLegacy.swift
//  FluxWidget
//
//  Legacy single-device Live Activity kept for backward compatibility
//  with existing push-to-start tokens. New installs use FluxWidgetMultiLiveActivity.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
import WidgetKit
import SwiftUI

struct FluxWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetAttributes.self) { context in
            FluxWidgetMultiContent(devices: [context.state.device], isStale: context.isStale)
        } dynamicIsland: { context in
            let devices = [context.state.device]
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(devices: devices)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(devices: devices)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(devices: devices)
                }
            } compactLeading: {
                IslandCompactLeading(devices: devices)
            } compactTrailing: {
                IslandCompactTrailing(devices: devices)
            } minimal: {
                IslandMinimal(devices: devices)
            }
            .widgetURL(URL(string: "fluxhaus://appliances"))
        }
    }
}
#endif
