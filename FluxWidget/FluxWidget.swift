//
//  FluxWidget.swift
//  FluxWidget
//
//  Created by David Jensenius on 2024-08-01.
//

import WidgetKit
import SwiftUI

class FluxWidgetNetwork {
    static func fetchStatus() async -> [WidgetDevice] {
        let password = WhereWeAre.getPassword()!

        // Simulate an asynchronous data fetching process.
        let loginData = try? await getFlux(password: password)
        let convertedData = convertLoginResponseToAppData(response: loginData!)
        let widgetData = convertDataToWidgetDevices(fluxData: convertedData)
        return classifyWidgetData(devices: widgetData)
    }

    static func classifyWidgetData(devices: [WidgetDevice]) -> [WidgetDevice] {
        var constantDevices: [WidgetDevice] = []
        var timedRunningDevices: [WidgetDevice] = []
        var runningDevices: [WidgetDevice] = []
        var offDevices: [WidgetDevice] = []

        devices.forEach { device in
            switch device.name {
            case "Car", "Battery":
                constantDevices.append(device)
            case "MopBot", "BroomBot":
                if device.running {
                    runningDevices.append(device)
                } else {
                    offDevices.append(device)
                }
            default:
                if device.running {
                    timedRunningDevices.append(device)
                } else {
                    offDevices.append(device)
                }
            }
        }
        timedRunningDevices = sortTimedDevices(devices: timedRunningDevices)
        var sortedDevices: [WidgetDevice] = timedRunningDevices
        sortedDevices += runningDevices
        sortedDevices += constantDevices
        sortedDevices += offDevices
        return sortedDevices
    }

    static func sortTimedDevices(devices: [WidgetDevice]) -> [WidgetDevice] {
        let sortedDevices = devices.sorted {
            $0.progress < $1.progress
        }
        return sortedDevices
    }
}

struct Provider: AppIntentTimelineProvider {
    let staticList = [
        WidgetDevice(
            name: "Dryer",
            progress: 75,
            icon: "dryer",
            trailingText: "Finishes at 3pm",
            shortText: "3:00pm",
            running: true
        ),
        WidgetDevice(
            name: "Washer",
            progress: 45,
            icon: "washer",
            trailingText: "Finishes at 4:12pm",
            shortText: "4:12pm",
            running: true
        ),
        WidgetDevice(
            name: "Dishwasher",
            progress: 15,
            icon: "dishwasher",
            trailingText: "Finishes at 5:43pm",
            shortText: "5:43pm",
            running: true
        ),
        WidgetDevice(
            name: "BroomBot",
            progress: 85,
            icon: "fan",
            trailingText: "85%",
            shortText: "On",
            running: true
        ),
        WidgetDevice(
            name: "MopBot",
            progress: 96,
            icon: "humidifier.and.droplets",
            trailingText: "96%",
            shortText: "Off",
            running: true
        ),
        WidgetDevice(
            name: "Car",
            progress: 45,
            icon: "car",
            trailingText: "45%",
            shortText: "200km",
            running: true
        )
    ]

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            widgetDevices: staticList
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, widgetDevices: staticList)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        var entries: [SimpleEntry] = []
        print("Getting list?")
        let theList = await FluxWidgetNetwork.fetchStatus()
        let currentDate = Date()
        for hourOffset in 0 ..< 2 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(date: entryDate, configuration: configuration, widgetDevices: theList)
            entries.append(entry)
        }
        print("Got all entries")
        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        print("Returning")
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let widgetDevices: [WidgetDevice]
}

struct DeviceListView: View {
    var limit: Int?
    var items: [WidgetDevice]

    var body: some View {
        VStack {
            ForEach(1 ... items.count, id: \.self) { index in
                let item = items[index-1]
                if limit == nil || index <= limit! {
                    HStack {
                        if item.progress > 0 {
                            ProgressView(value: Double(item.progress) / 100) {
                                HStack {
                                    Image(systemName: item.icon)
                                    Text(item.name)
                                }
                            } currentValueLabel: {
                                Text(item.trailingText)
                            }.padding(.bottom)
                        } else if item.running {
                            HStack {
                                Image(systemName: item.icon)
                                Text(item.trailingText)
                                Spacer()
                            }
                            .padding(.bottom)
                        } else {
                            HStack {
                                Image(systemName: item.icon)
                                Text("\(item.name) off")
                                Spacer()
                            }.padding(.bottom)
                        }
                    }
                }
            }
        }
    }
}

struct DeviceGridView: View {
    var limit: Int?
    var items: [WidgetDevice]

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 40) {
            ForEach(1 ... items.count, id: \.self) { index in
                if limit == nil || index <= limit! {
                    SingleView(item: items[index - 1])
                }
            }
        }
    }
}

struct SmallDeviceGridView: View {
    var limit: Int?
    var items: [WidgetDevice]

    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 15) {
            ForEach(1 ... items.count, id: \.self) { index in
                if limit == nil || index <= limit! {
                    SingleView(item: items[index - 1], multipleLines: false)
                }
            }
        }
    }
}

struct InlineView: View {
    var item: WidgetDevice
    var body: some View {
        HStack {
            Image(systemName: item.icon)
            Text(item.trailingText)
        }
    }
}

struct SingleView: View {
    var item: WidgetDevice
    var multipleLines = true

    var body: some View {
        VStack {
            Gauge(
                value: Double(item.progress) / 100,
                label: { Image(systemName: item.icon) },
                currentValueLabel: {
                    if multipleLines && item.shortText != "" {
                        Text("\(item.progress)%")
                    } else {
                        Text(item.shortText)
                    }
                }
            )
            .gaugeStyle(.accessoryCircular)
            if multipleLines && item.shortText != "" {
                Text(item.shortText)
            }
        }
    }
}

struct FluxWidgetEntryView: View {
    var entry: Provider.Entry
    var grid = false
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            if grid {
                SmallDeviceGridView(limit: 4, items: entry.widgetDevices)
            } else {
                SingleView(item: entry.widgetDevices[0])
            }
        case .systemMedium:
            DeviceListView(limit: 2, items: entry.widgetDevices)
        case .systemLarge:
            DeviceGridView(limit: nil, items: entry.widgetDevices)
        case .systemExtraLarge:
            DeviceGridView(limit: nil, items: entry.widgetDevices)
        case .accessoryCircular:
            SingleView(item: entry.widgetDevices[0], multipleLines: false)
        case .accessoryRectangular:
            DeviceListView(limit: 1, items: entry.widgetDevices)
        case .accessoryInline:
            InlineView(item: entry.widgetDevices[0])
        default:
            EmptyView()
        }
    }
}

struct FluxWidget: Widget {
    let kind: String = "FluxWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FluxWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct FluxWidgetOtherSmall: Widget {
    let kind: String = "FluxWidgetSmall"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FluxWidgetEntryView(entry: entry, grid: true)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([
            .systemSmall
        ])
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        return intent
    }

    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        return intent
    }
}

let staticList = [
    WidgetDevice(
        name: "Dryer",
        progress: 75,
        icon: "dryer",
        trailingText: "Finishes at 3pm",
        shortText: "25m",
        running: true
    ),
    WidgetDevice(
        name: "Washer",
        progress: 45,
        icon: "washer",
        trailingText: "Finishes at 4:12pm",
        shortText: "4:12pm",
        running: true
    ),
    WidgetDevice(
        name: "Dishwasher",
        progress: 15,
        icon: "dishwasher",
        trailingText: "Finishes at 5:43pm",
        shortText: "5:43pm",
        running: true
    ),
    WidgetDevice(
        name: "BroomBot",
        progress: 85,
        icon: "fan",
        trailingText: "85%",
        shortText: "Off",
        running: true
    ),
    WidgetDevice(
        name: "MopBot",
        progress: 96,
        icon: "humidifier.and.droplets",
        trailingText: "96%",
        shortText: "On",
        running: true
    ),
    WidgetDevice(
        name: "Car",
        progress: 45,
        icon: "car",
        trailingText: "45%",
        shortText: "200km",
        running: true
    )
]

#Preview(as: .systemSmall) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .systemSmall) {
    FluxWidgetOtherSmall()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .systemMedium) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .systemLarge) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .systemExtraLarge) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .accessoryCircular) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .accessoryRectangular) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}

#Preview(as: .accessoryInline) {
    FluxWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, widgetDevices: staticList)
}
