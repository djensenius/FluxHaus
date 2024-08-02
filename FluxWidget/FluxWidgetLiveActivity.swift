//
//  FluxWidgetLiveActivity.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

#if !targetEnvironment(macCatalyst)
import ActivityKit
import WidgetKit
import SwiftUI

struct WidgetDevice: Codable, Equatable, Hashable {
    var name: String
    var progress: Double
    var icon: String
    var trailingText: String
    var shortText: String
}

struct FluxWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var device: WidgetDevice
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FluxWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                ProgressView(value: context.state.device.progress) {
                    HStack {
                        Image(systemName: context.state.device.icon)
                        Text(context.state.device.name)
                    }
                } currentValueLabel: {
                    Text(context.state.device.trailingText)
                }.padding(15)
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.device.icon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.device.shortText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.device.progress) {
                        HStack {
                            Text(context.state.device.name)
                        }
                    } currentValueLabel: {
                        Text(context.state.device.trailingText)
                    }.padding(5)
                    // more content
                }
            } compactLeading: {
                Image(systemName: context.state.device.icon)
            } compactTrailing: {
                ProgressView(value: context.state.device.progress)
                    .progressViewStyle(.circular)
            } minimal: {
                Image(systemName: context.state.device.icon)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension FluxWidgetAttributes {
    fileprivate static var preview: FluxWidgetAttributes {
        FluxWidgetAttributes(name: "World")
    }
}

extension FluxWidgetAttributes.ContentState {
    fileprivate static var dishwasher: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(
            device:
                WidgetDevice(
                    name: "Dishwasher",
                    progress: 0.5,
                    icon: "dishwasher",
                    trailingText: "Finished in 59 minutes",
                    shortText: "59m"
                )
        )
     }

     fileprivate static var dryer: FluxWidgetAttributes.ContentState {
         FluxWidgetAttributes.ContentState(
            device:
                WidgetDevice(
                    name: "Dryer",
                    progress: 0.25,
                    icon: "dryer",
                    trailingText: "Finished at 3pm",
                    shortText: "3:00pm"
                )
         )
     }
}

#Preview("Notification", as: .content, using: FluxWidgetAttributes.preview) {
   FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.dishwasher
    FluxWidgetAttributes.ContentState.dryer
}
#endif
