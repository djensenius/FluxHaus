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

struct FluxWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct FluxWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FluxWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
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
    fileprivate static var smiley: FluxWidgetAttributes.ContentState {
        FluxWidgetAttributes.ContentState(emoji: "😀")
     }

     fileprivate static var starEyes: FluxWidgetAttributes.ContentState {
         FluxWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: FluxWidgetAttributes.preview) {
   FluxWidgetLiveActivity()
} contentStates: {
    FluxWidgetAttributes.ContentState.smiley
    FluxWidgetAttributes.ContentState.starEyes
}
#endif
