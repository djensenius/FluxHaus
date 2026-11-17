//
//  ThermostatControlView.swift
//  FluxHaus
//
//  The Climate section's thermostat card: current conditions, setpoint
//  steppers, and HVAC mode / comfort preset / fan / schedule controls.
//

import SwiftUI

struct ThermostatControlCard: View {
    var thermostat: Thermostat

    var body: some View {
        if let state = thermostat.state, let status = state.thermostat {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                header(state: state, status: status)
                setpoints(state: state)
                Group {
                    modePicker
                    if !thermostat.presets.isEmpty || status.presetMode != nil {
                        presetMenu
                    }
                    if !thermostat.fanModes.isEmpty {
                        fanPicker
                    }
                }
                .disabled(!thermostat.canControl)
                footer
            }
            .padding()
            #if !os(visionOS)
            .background(Theme.Colors.secondaryBackground)
            #endif
            .cornerRadius(Theme.cornerRadius)
            #if os(visionOS)
            .glassBackgroundEffect()
            #endif
        }
    }

    // MARK: Header

    private func header(state: IndoorClimateState, status: ThermostatStatus) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(status))
                    .font(Theme.Fonts.bodySmall).fontWeight(.semibold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                Text(state.primaryTemperature.map { format($0, unit: state.unit, precise: true) } ?? "—")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                let summary = ThermostatSummary(thermostat: status) { format($0, unit: state.unit) }
                Label(summary.text, systemImage: summary.systemImage)
                    .foregroundColor(summary.activity == .unavailable ? Theme.Colors.warning : Theme.Colors.textPrimary)
                if let humidity = status.currentHumidity {
                    Label("\(IndoorClimateFormat.humidity(humidity)) humidity", systemImage: "humidity")
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .font(Theme.Fonts.bodyMedium)
            .multilineTextAlignment(.trailing)
        }
    }

    private func title(_ status: ThermostatStatus) -> String {
        guard let area = status.area, !area.isEmpty else { return "Thermostat" }
        return "Thermostat · \(area)"
    }

    // MARK: Setpoints

    @ViewBuilder
    private func setpoints(state: IndoorClimateState) -> some View {
        if thermostat.mode?.lowercased() == "off" {
            Label("Heating and cooling are off", systemImage: "power")
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
        } else if thermostat.isAutoMode {
            HStack(spacing: Theme.Spacing.large) {
                SetpointStepper(
                    title: "Heat to", value: thermostat.targetLow, unit: state.unit,
                    tint: Theme.Colors.accent, isPending: thermostat.pendingLow != nil,
                    isEnabled: thermostat.canControl
                ) { thermostat.nudgeLow(by: $0) }
                SetpointStepper(
                    title: "Cool to", value: thermostat.targetHigh, unit: state.unit,
                    tint: Theme.Colors.info, isPending: thermostat.pendingHigh != nil,
                    isEnabled: thermostat.canControl
                ) { thermostat.nudgeHigh(by: $0) }
            }
        } else {
            let cooling = thermostat.mode?.lowercased() == "cool"
            SetpointStepper(
                title: cooling ? "Cool to" : "Heat to", value: thermostat.target, unit: state.unit,
                tint: cooling ? Theme.Colors.info : Theme.Colors.accent,
                isPending: thermostat.pendingTarget != nil,
                isEnabled: thermostat.canControl
            ) { thermostat.nudgeTarget(by: $0) }
        }
    }

    // MARK: Controls

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { thermostat.mode ?? "" },
            set: { mode in Task { await thermostat.setMode(mode) } }
        )) {
            ForEach(thermostat.modes, id: \.self) { mode in
                Label(ThermostatLabels.mode(mode), systemImage: ThermostatLabels.modeIcon(mode))
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Mode")
    }

    private var presetMenu: some View {
        HStack {
            Label("Comfort", systemImage: "slider.horizontal.3")
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Menu {
                ForEach(thermostat.presets, id: \.self) { preset in
                    Button {
                        Task { await thermostat.setPreset(preset) }
                    } label: {
                        if preset == thermostat.preset {
                            Label(ThermostatLabels.preset(preset), systemImage: "checkmark")
                        } else {
                            Text(ThermostatLabels.preset(preset))
                        }
                    }
                }
            } label: {
                Text(presetTitle)
                    .font(Theme.Fonts.bodyMedium).fontWeight(.semibold)
            }
            .fixedSize()
            .disabled(thermostat.presets.isEmpty)
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private var presetTitle: String {
        guard let preset = thermostat.preset, !preset.isEmpty, preset.lowercased() != "none" else {
            return "Schedule"
        }
        return ThermostatLabels.preset(preset)
    }

    private var fanPicker: some View {
        HStack {
            Label("Fan", systemImage: "fan")
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Picker("Fan", selection: Binding(
                get: { thermostat.fan ?? "" },
                set: { fan in Task { await thermostat.setFan(fan) } }
            )) {
                ForEach(thermostat.fanModes, id: \.self) { fan in
                    Text(ThermostatLabels.fan(fan)).tag(fan)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .font(Theme.Fonts.bodyMedium)
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await thermostat.resumeSchedule() }
            } label: {
                Label("Resume schedule", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.bordered)
            .disabled(!thermostat.canControl || thermostat.isSending)
            Spacer()
            if thermostat.isSending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Updating thermostat")
            } else if let error = thermostat.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.warning)
                    .lineLimit(2)
            }
        }
    }

    private func format(_ value: Double, unit: String, precise: Bool = false) -> String {
        IndoorClimateFormat.temperature(value, unit: unit, precise: precise)
    }
}

/// A − value + control for one setpoint, also adjustable with VoiceOver swipes.
struct SetpointStepper: View {
    let title: String
    let value: Double?
    let unit: String
    let tint: Color
    let isPending: Bool
    let isEnabled: Bool
    let onStep: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Theme.Fonts.bodySmall)
                .foregroundColor(Theme.Colors.textSecondary)
            HStack(spacing: Theme.Spacing.medium) {
                stepButton(-1, symbol: "minus")
                Text(formatted)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundColor(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(isPending ? 0.6 : 1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                stepButton(1, symbol: "plus")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(formatted)
        .accessibilityAdjustableAction { direction in
            guard isEnabled, value != nil else { return }
            switch direction {
            case .increment: onStep(1)
            case .decrement: onStep(-1)
            @unknown default: break
            }
        }
    }

    private var formatted: String {
        value.map { IndoorClimateFormat.temperature($0, unit: unit, precise: false) } ?? "—"
    }

    private func stepButton(_ steps: Int, symbol: String) -> some View {
        Button {
            onStep(steps)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!isEnabled || value == nil)
    }
}
