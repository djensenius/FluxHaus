//
//  AppliancesDetailView.swift
//  FluxHaus
//
//  Created by Copilot on 2026-03-09.
//

import SwiftUI

struct AppliancesDetailView: View {
    @ObservedObject var hconn: HomeConnect
    @ObservedObject var miele: Miele
    @ObservedObject var apiResponse: Api

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let response = apiResponse.response {
                    dishwasherCard(response: response)
                    washerCard(response: response)
                    dryerCard(response: response)
                }
            }
            .padding()
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
    }

    @ViewBuilder
    private func dishwasherCard(response: LoginResponse) -> some View {
        let dishwasher = response.dishwasher
        applianceCard(
            icon: "dishwasher",
            name: "Dishwasher",
            iconColor: dishwasherIconColor(dishwasher: dishwasher)
        ) {
            if let dw = dishwasher {
                dishwasherDetails(dw: dw)
            } else {
                noDataLabel()
            }
        }
    }

    @ViewBuilder
    private func washerCard(response: LoginResponse) -> some View {
        let washer = response.washer
        applianceCard(
            icon: "washer",
            name: "Washing Machine",
            iconColor: washerDryerIconColor(wd: washer)
        ) {
            if let wd = washer {
                washerDryerDetails(wd: wd)
            } else {
                noDataLabel()
            }
        }
    }

    @ViewBuilder
    private func dryerCard(response: LoginResponse) -> some View {
        let dryer = response.dryer
        applianceCard(
            icon: "dryer",
            name: "Dryer",
            iconColor: washerDryerIconColor(wd: dryer)
        ) {
            if let wd = dryer {
                washerDryerDetails(wd: wd)
            } else {
                noDataLabel()
            }
        }
    }

    @ViewBuilder
    private func applianceCard<Content: View>(
        icon: String,
        name: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(iconColor)
                Text(name)
                    .font(Theme.Fonts.headerXL())
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(visionOS)
        .glassBackgroundEffect(in: .rect(cornerRadius: 12))
        #else
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(12)
        #endif
    }

    @ViewBuilder
    private func noDataLabel() -> some View {
        Label("No data available", systemImage: "questionmark.circle")
            .font(Theme.Fonts.bodyMedium)
            .foregroundColor(Theme.Colors.textSecondary)
    }

    // MARK: - Dishwasher Details

    @ViewBuilder
    private func dishwasherDetails(dw: DishWasher) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(
                label: "Status",
                value: operationStateDisplay(dw.operationState),
                icon: operationStateIcon(dw.operationState),
                color: operationStateColor(dw.operationState)
            )

            detailRow(label: "Door", value: dw.doorState, icon: doorIcon(dw.doorState))

            if let program = dw.activeProgram {
                detailRow(label: "Program", value: programDisplay(program), icon: "list.bullet")
            } else if let selected = dw.selectedProgram, !selected.isEmpty {
                detailRow(label: "Selected Program", value: selected, icon: "list.bullet")
            }

            if let progress = dw.programProgress, progress > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                        Text("\(Int(progress))%")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    ProgressView(value: progress, total: 100)
                        .tint(Theme.Colors.accent)
                }
            }

            if dw.operationState == .run || dw.operationState == .pause {
                if let remaining = dw.remainingTime, remaining > 0 {
                    let minutes = remaining / 60
                    let finishTime = finishTimeString(minutesRemaining: minutes)
                    detailRow(
                        label: "Time Remaining",
                        value: "\(minutes) min (done ~\(finishTime))",
                        icon: "hourglass"
                    )
                }
            }

            if dw.operationState == .delayedStart {
                if let startIn = dw.startInRelative, startIn > 0 {
                    detailRow(
                        label: "Starts In",
                        value: "\(startIn) \(dw.startInRelativeUnit ?? "sec")",
                        icon: "clock.arrow.circlepath"
                    )
                }
            }
        }
    }

    // MARK: - Washer/Dryer Details

    @ViewBuilder
    private func washerDryerDetails(wd: WasherDryer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if wd.inUse {
                detailRow(
                    label: "Status",
                    value: wd.status ?? "Running",
                    icon: "play.circle.fill",
                    color: Theme.Colors.accent
                )

                if let programName = wd.programName,
                   !programName.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Program",
                        value: programName.trimmingCharacters(in: .whitespaces),
                        icon: "list.bullet"
                    )
                }

                if let step = wd.step,
                   !step.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Step",
                        value: step.trimmingCharacters(in: .whitespaces),
                        icon: "arrow.triangle.2.circlepath"
                    )
                }

                if let running = wd.timeRunning, running > 0 {
                    detailRow(
                        label: "Running For",
                        value: "\(running) min",
                        icon: "timer"
                    )
                }

                if let remaining = wd.timeRemaining, remaining > 0 {
                    let finishTime = finishTimeString(minutesRemaining: remaining)
                    detailRow(
                        label: "Time Remaining",
                        value: "\(remaining) min (done ~\(finishTime))",
                        icon: "hourglass"
                    )
                }
            } else {
                detailRow(
                    label: "Status",
                    value: wd.status ?? "Off",
                    icon: "power.circle",
                    color: Theme.Colors.textSecondary
                )

                if let programName = wd.programName,
                   !programName.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Last Program",
                        value: programName.trimmingCharacters(in: .whitespaces),
                        icon: "list.bullet"
                    )
                }

                if let step = wd.step,
                   !step.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Last Step",
                        value: step.trimmingCharacters(in: .whitespaces),
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func detailRow(
        label: String,
        value: String,
        icon: String,
        color: Color = Theme.Colors.textPrimary
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.bodyMedium)
                .foregroundColor(color)
        }
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private func finishTimeString(minutesRemaining: Int) -> String {
        let finishTime = Calendar.current.date(
            byAdding: .minute,
            value: minutesRemaining,
            to: Date()
        ) ?? Date()
        return Self.timeFormatter.string(from: finishTime)
    }

    private func operationStateDisplay(_ state: OperationState) -> String {
        switch state {
        case .inactive: return "Inactive"
        case .ready: return "Ready"
        case .delayedStart: return "Delayed Start"
        case .run: return "Running"
        case .pause: return "Paused"
        case .actionRequired: return "Action Required"
        case .finished: return "Finished"
        case .error: return "Error"
        case .aborting: return "Aborting"
        }
    }

    private func operationStateIcon(_ state: OperationState) -> String {
        switch state {
        case .inactive: return "power.circle"
        case .ready: return "checkmark.circle"
        case .delayedStart: return "clock.arrow.circlepath"
        case .run: return "play.circle.fill"
        case .pause: return "pause.circle.fill"
        case .actionRequired: return "exclamationmark.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .aborting: return "stop.circle.fill"
        }
    }

    private func operationStateColor(_ state: OperationState) -> Color {
        switch state {
        case .inactive: return Theme.Colors.textSecondary
        case .ready: return Theme.Colors.textPrimary
        case .delayedStart: return Theme.Colors.info
        case .run: return Theme.Colors.accent
        case .pause: return Theme.Colors.warning
        case .actionRequired: return Theme.Colors.warning
        case .finished: return Theme.Colors.success
        case .error: return Theme.Colors.error
        case .aborting: return Theme.Colors.error
        }
    }

    private func doorIcon(_ doorState: String) -> String {
        doorState == "Open" ? "door.left.hand.open" : "door.left.hand.closed"
    }

    private func programDisplay(_ program: DishWasherProgram) -> String {
        switch program {
        case .preRinse: return "Pre-Rinse"
        case .auto1: return "Auto 1"
        case .auto2: return "Auto 2"
        case .auto3: return "Auto 3"
        case .eco50: return "Eco 50°"
        case .quick45: return "Quick 45'"
        case .intensiv70: return "Intensive 70°"
        case .normal65: return "Normal 65°"
        case .glas40: return "Glass 40°"
        case .glassCare: return "Glass Care"
        case .nightWash: return "Night Wash"
        case .quick65: return "Quick 65'"
        case .normal45: return "Normal 45°"
        case .intensiv45: return "Intensive 45°"
        case .autoHalfLoad: return "Auto Half Load"
        case .intensivPower: return "Intensive Power"
        case .magicDaily: return "Magic Daily"
        case .super60: return "Super 60°"
        case .kurz60: return "Short 60'"
        case .expressSparkle65: return "Express Sparkle 65°"
        case .machineCare: return "Machine Care"
        case .steamFresh: return "Steam Fresh"
        case .maximumCleaning: return "Maximum Cleaning"
        case .mixedLoad: return "Mixed Load"
        }
    }

    private func dishwasherIconColor(dishwasher: DishWasher?) -> Color {
        guard let dw = dishwasher else { return Theme.Colors.textSecondary }
        switch dw.operationState {
        case .run: return Theme.Colors.accent
        case .finished: return Theme.Colors.success
        case .error, .aborting: return Theme.Colors.error
        case .pause, .actionRequired: return Theme.Colors.warning
        default: return Theme.Colors.textSecondary
        }
    }

    private func washerDryerIconColor(wd: WasherDryer?) -> Color {
        guard let wd = wd else { return Theme.Colors.textSecondary }
        if wd.inUse { return Theme.Colors.accent }
        if wd.status == "Finished" { return Theme.Colors.success }
        return Theme.Colors.textSecondary
    }
}

#if DEBUG
#Preview {
    AppliancesDetailView(
        hconn: MockData.createHomeConnect(),
        miele: MockData.createMiele(),
        apiResponse: MockData.createApi()
    )
}
#endif
