//
//  AirPurifierView.swift
//  FluxHaus
//
//  Blue Pure air purifier controls.
//

import SwiftUI

struct AirPurifierView: View {
    @Bindable var purifier: AirPurifier

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            fanControls
            presetControls
            lightControls
            filterFooter
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
    }

    private var header: some View {
        HStack {
            Image(systemName: "air.purifier.fill")
                .font(Theme.Fonts.headerLarge())
                .foregroundColor(Theme.Colors.accent)
            VStack(alignment: .leading) {
                Text("Air Purifier")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(purifier.status.online ? "Online" : "Offline")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundColor(purifier.status.online ? Theme.Colors.success : Theme.Colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(purifier.formattedPm25)
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("PM2.5")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private var fanControls: some View {
        Toggle(isOn: Binding(
            get: { purifier.status.fanOn },
            set: { purifier.setFan(on: $0) }
        )) {
            Label("Fan", systemImage: "fan.fill")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .tint(Theme.Colors.accent)
    }

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(Theme.Colors.textSecondary)
            HStack {
                ForEach(presetOptions, id: \.self) { mode in
                    Button {
                        purifier.setPreset(mode: mode)
                    } label: {
                        Text(mode.capitalized)
                            .font(Theme.Fonts.bodyMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                purifier.status.presetMode == mode
                                    ? Theme.Colors.accent
                                    : Theme.Colors.background
                            )
                            .foregroundColor(
                                purifier.status.presetMode == mode
                                    ? Theme.Colors.background
                                    : Theme.Colors.textPrimary
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lightControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { purifier.status.lightOn },
                set: { purifier.setLight(on: $0) }
            )) {
                Label("LED Light", systemImage: "lightbulb.fill")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.accent)
        }
    }

    private var filterFooter: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundColor(Theme.Colors.textSecondary)
            Text("Filter life")
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(purifier.formattedFilterLife)
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private var presetOptions: [String] {
        purifier.status.presetModes.isEmpty ? ["auto", "night"] : purifier.status.presetModes
    }
}

/// Sheet wrapper presenting the air purifier controls, mirroring
/// RobotDetailView so the purifier can be opened from the appliances grid.
struct AirPurifierDetailView: View {
    @Bindable var purifier: AirPurifier

    var body: some View {
        NavigationStack {
            ScrollView {
                AirPurifierView(purifier: purifier)
                    .padding()
            }
            #if os(visionOS)
            .glassBackgroundEffect()
            #else
            .background(Theme.Colors.background)
            #endif
            .navigationTitle("Air Purifier")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

#if DEBUG
#Preview {
    AirPurifierView(purifier: {
        let purifier = AirPurifier()
        purifier.status = AirPurifierState(
            online: true,
            fanOn: true,
            presetMode: "auto",
            presetModes: ["auto", "night"],
            lightOn: true,
            brightness: 255,
            pm25: 4,
            filterLife: 100
        )
        return purifier
    }())
}
#endif
