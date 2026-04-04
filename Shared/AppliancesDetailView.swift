//
//  AppliancesDetailView.swift
//  FluxHaus
//
import SwiftUI

struct AppliancesDetailView: View {
    @ObservedObject var hconn: HomeConnect
    @ObservedObject var miele: Miele
    @ObservedObject var apiResponse: Api
    var robots: Robots
    @State private var showBroomBotSheet = false
    @State private var showMopBotSheet = false
    @State private var robotActionPending: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let response = apiResponse.response {
                    dishwasherCard(response: response)
                    washerCard(response: response)
                    dryerCard(response: response)
                }
                robotCard(robot: robots.broomBot)
                robotCard(robot: robots.mopBot)
            }
            .padding()
        }
        .sheet(isPresented: $showBroomBotSheet) {
            RobotDetailView(robot: robots.broomBot, robots: robots)
        }
        .sheet(isPresented: $showMopBotSheet) {
            RobotDetailView(robot: robots.mopBot, robots: robots)
        }
        #if os(visionOS)
        .glassBackgroundEffect()
        #else
        .background(Theme.Colors.background)
        #endif
    }

    @ViewBuilder
    private func robotCard(robot: Robot) -> some View {
        let isActive = robot.running == true || robot.paused == true
        let isPending = robotActionPending == robot.name
        applianceCard(
            icon: robot.name == "MopBot" ? "humidifier.and.droplets" : "fan.fill",
            name: robot.name ?? "Robot",
            iconColor: robotIconColor(robot)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                robotDetails(robot: robot, isActive: isActive)
                HStack(spacing: 10) {
                    if isActive {
                        Button {
                            performRobotAction(action: "stop", robot: robot)
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Colors.error)
                        .disabled(isPending)
                    } else {
                        Button {
                            performRobotAction(action: "start", robot: robot)
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Colors.accent)
                        .disabled(isPending)
                    }
                    Button {
                        if robot.name == "BroomBot" {
                            showBroomBotSheet = true
                        } else {
                            showMopBotSheet = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func robotDetails(robot: Robot, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(
                label: "Status",
                value: robotStatusText(robot),
                icon: robotStatusIcon(robot),
                color: robotIconColor(robot)
            )
            if let battery = robot.batteryLevel {
                detailRow(
                    label: "Battery",
                    value: "\(battery)%\(robot.charging == true ? " ⚡" : "")",
                    icon: batteryIcon(battery)
                )
            }
            if robot.binFull == true {
                detailRow(label: "Bin", value: "Full", icon: "trash.fill", color: Theme.Colors.warning)
            }
            if isActive, let started = robot.timeStarted, !started.isEmpty {
                detailRow(label: "Started", value: relativeTimeString(from: started), icon: "clock")
            }
        }
    }

    @ViewBuilder
    private func dishwasherCard(response: LoginResponse) -> some View {
        let dishwasher = response.dishwasher
        applianceCard(
            icon: "dishwasher",
            name: "Dishwasher",
            iconColor: dishwasherIconColor(dishwasher: dishwasher)
        ) {
            if let dwm = dishwasher {
                dishwasherDetails(dwm: dwm)
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
            iconColor: washerDryerIconColor(wdm: washer)
        ) {
            if let wdm = washer {
                washerDryerDetails(wdm: wdm)
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
            iconColor: washerDryerIconColor(wdm: dryer)
        ) {
            if let wdm = dryer {
                washerDryerDetails(wdm: wdm)
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
                    .font(Theme.Fonts.headerLarge())
                    .foregroundColor(iconColor)
                Text(name)
                    .font(Theme.Fonts.headerLarge())
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

    @ViewBuilder
    private func dishwasherDetails(dwm: DishWasher) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(
                label: "Status",
                value: operationStateDisplay(dwm.operationState),
                icon: operationStateIcon(dwm.operationState),
                color: operationStateColor(dwm.operationState)
            )

            detailRow(label: "Door", value: dwm.doorState, icon: doorIcon(dwm.doorState))

            if let program = dwm.activeProgram {
                detailRow(label: "Program", value: programDisplay(program), icon: "list.bullet")
            } else if let selected = dwm.selectedProgram, !selected.isEmpty {
                detailRow(label: "Selected Program", value: selected, icon: "list.bullet")
            }

            if let progress = dwm.programProgress, progress > 0 {
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

            if dwm.operationState == .run || dwm.operationState == .pause {
                if let remaining = dwm.remainingTime, remaining > 0 {
                    let minutes = remaining / 60
                    let finishTime = finishTimeString(minutesRemaining: minutes)
                    detailRow(
                        label: "Time Remaining",
                        value: "\(formatDurationMinutes(minutes)) (done ~\(finishTime))",
                        icon: "hourglass"
                    )
                }
            }

            if dwm.operationState == .delayedStart {
                if let startIn = dwm.startInRelative, startIn > 0 {
                    detailRow(
                        label: "Starts In",
                        value: "\(startIn) \(dwm.startInRelativeUnit ?? "sec")",
                        icon: "clock.arrow.circlepath"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func washerDryerDetails(wdm: WasherDryer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if wdm.inUse {
                detailRow(
                    label: "Status",
                    value: wdm.status ?? "Running",
                    icon: "play.circle.fill",
                    color: Theme.Colors.accent
                )

                if let programName = wdm.programName,
                   !programName.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Program",
                        value: formatApplianceProgramName(programName),
                        icon: "list.bullet"
                    )
                }

                if let step = wdm.step,
                   !step.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Step",
                        value: formatApplianceProgramName(step),
                        icon: "arrow.triangle.2.circlepath"
                    )
                }

                if let running = wdm.timeRunning, running > 0 {
                    detailRow(
                        label: "Running For",
                        value: formatDurationMinutes(running),
                        icon: "timer"
                    )
                }

                if let remaining = wdm.timeRemaining, remaining > 0 {
                    let finishTime = finishTimeString(minutesRemaining: remaining)
                    detailRow(
                        label: "Time Remaining",
                        value: "\(formatDurationMinutes(remaining)) (done ~\(finishTime))",
                        icon: "hourglass"
                    )
                }
            } else {
                detailRow(
                    label: "Status",
                    value: wdm.status ?? "Off",
                    icon: "power.circle",
                    color: Theme.Colors.textSecondary
                )

                if let programName = wdm.programName,
                   !programName.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Last Program",
                        value: formatApplianceProgramName(programName),
                        icon: "list.bullet"
                    )
                }

                if let step = wdm.step,
                   !step.trimmingCharacters(in: .whitespaces).isEmpty {
                    detailRow(
                        label: "Last Step",
                        value: formatApplianceProgramName(step),
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
    }

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
}

private extension AppliancesDetailView {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    func finishTimeString(minutesRemaining: Int) -> String {
        let finishTime = Calendar.current.date(
            byAdding: .minute, value: minutesRemaining, to: Date()
        ) ?? Date()
        return Self.timeFormatter.string(from: finishTime)
    }
    func operationStateDisplay(_ state: OperationState) -> String {
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
    func operationStateIcon(_ state: OperationState) -> String {
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
    func operationStateColor(_ state: OperationState) -> Color {
        switch state {
        case .inactive: return Theme.Colors.textSecondary
        case .ready: return Theme.Colors.textPrimary
        case .delayedStart: return Theme.Colors.info
        case .run: return Theme.Colors.accent
        case .pause, .actionRequired: return Theme.Colors.warning
        case .finished: return Theme.Colors.success
        case .error, .aborting: return Theme.Colors.error
        }
    }
    func doorIcon(_ doorState: String) -> String {
        doorState == "Open" ? "door.left.hand.open" : "door.left.hand.closed"
    }
    func programDisplay(_ program: DishWasherProgram) -> String {
        program.displayName
    }
    func dishwasherIconColor(dishwasher: DishWasher?) -> Color {
        guard let dwm = dishwasher else { return Theme.Colors.textSecondary }
        switch dwm.operationState {
        case .run: return Theme.Colors.accent
        case .finished: return Theme.Colors.success
        case .error, .aborting: return Theme.Colors.error
        case .pause, .actionRequired: return Theme.Colors.warning
        default: return Theme.Colors.textSecondary
        }
    }
    func washerDryerIconColor(wdm: WasherDryer?) -> Color {
        guard let wdm = wdm else { return Theme.Colors.textSecondary }
        if wdm.inUse { return Theme.Colors.accent }
        if wdm.status == "Finished" { return Theme.Colors.success }
        return Theme.Colors.textSecondary
    }

    func robotStatusText(_ robot: Robot) -> String {
        if robot.running == true { return "Running" }
        if robot.paused == true { return "Paused" }
        if robot.docking == true { return "Docking" }
        if robot.charging == true { return "Charging" }
        return "Idle"
    }
    func robotStatusIcon(_ robot: Robot) -> String {
        if robot.running == true { return "play.circle.fill" }
        if robot.paused == true { return "pause.circle.fill" }
        if robot.docking == true { return "arrow.down.to.line" }
        if robot.charging == true { return "bolt.fill" }
        return "power.circle"
    }
    func robotIconColor(_ robot: Robot) -> Color {
        if robot.running == true { return Theme.Colors.accent }
        if robot.paused == true { return Theme.Colors.warning }
        if robot.charging == true { return Theme.Colors.info }
        return Theme.Colors.textSecondary
    }
    func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25percent"
        case 25..<50: return "battery.50percent"
        case 50..<75: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    func performRobotAction(action: String, robot: Robot) {
        guard let name = robot.name else { return }
        robotActionPending = name
        robots.performAction(action: action, robot: name)
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task { @MainActor in
                robots.fetchRobots()
                robotActionPending = nil
            }
        }
    }
}
#if DEBUG
#Preview {
    AppliancesDetailView(
        hconn: MockData.createHomeConnect(),
        miele: MockData.createMiele(),
        apiResponse: MockData.createApi(),
        robots: MockData.createRobots()
    )
}
#endif
