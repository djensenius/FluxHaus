//
//  FluxWidgetLiveActivityLegacy.swift
//  FluxWidget
//
//  Legacy single-device Live Activity kept for backward compatibility
//  with existing push-to-start tokens. New installs use FluxWidgetMultiLiveActivity.
//

#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

struct FluxWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetAttributes.self) { context in
            let device = context.state.device
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: device.icon)
                        .font(.title3)
                        .foregroundStyle(tintColor(for: device.name))
                    Text(device.name)
                        .font(.headline)
                    Spacer()
                    if !device.shortText.isEmpty {
                        Text(device.shortText)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(tintColor(for: device.name))
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("") }
                DynamicIslandExpandedRegion(.trailing) { Text("") }
                DynamicIslandExpandedRegion(.bottom) { Text("") }
            } compactLeading: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            } compactTrailing: {
                Text("")
            } minimal: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            }
        }
    }
}
#endif
