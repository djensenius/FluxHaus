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
            PhoneSingleDeviceView(device: context.state.device)
                .padding(16)
                .activityBackgroundTint(liveActivityBackgroundTint(for: [context.state.device]))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityIconBubble(device: context.state.device, size: 34, iconSize: .headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(deviceMetricText(context.state.device))
                            .font(Theme.Fonts.headerLarge())
                            .lineLimit(1)
                            .foregroundStyle(liveActivityProgressColor(for: context.state.device))
                        Text(trailingSubtitle(for: context.state.device))
                            .font(Theme.Fonts.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityProgressLine(device: context.state.device)
                }
            } compactLeading: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            } compactTrailing: {
                Text(deviceMetricText(context.state.device))
                    .font(Theme.Fonts.bodyMedium)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(liveActivityProgressColor(for: context.state.device))
            } minimal: {
                Image(systemName: context.state.device.icon)
                    .foregroundStyle(tintColor(for: context.state.device.name))
            }
        }
    }
}
#endif
