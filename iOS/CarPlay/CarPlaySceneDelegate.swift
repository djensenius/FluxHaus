//
//  CarPlaySceneDelegate.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-04-18.
//

import CarPlay
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "CarPlay")

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var voiceManager: CarPlayVoiceManager?
    private var latestResponse: LoginResponse?
    private var refreshTimer: Timer?
    private var assistantTemplate: CPInformationTemplate?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Scene lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        logger.info("CarPlay connected")

        NotificationCenter.default.addObserver(
            self, selector: #selector(dataDidUpdate(_:)),
            name: .dataUpdated, object: nil
        )

        voiceManager = CarPlayVoiceManager()
        voiceManager?.onStateChange = { [weak self] state in
            self?.updateAssistantItem(for: state)
        }

        Task {
            await loadInitialData()
            await MainActor.run { buildUI() }
        }

        startRefreshTimer()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        logger.info("CarPlay disconnected")
        stopRefreshTimer()
        voiceManager?.cleanup()
        voiceManager = nil
        self.interfaceController = nil
    }

    // MARK: - Data loading

    private func loadInitialData() async {
        let hasToken = await AuthManager.shared.ensureValidToken()
        guard hasToken || WhereWeAre.getPassword() != nil else {
            logger.warning("CarPlay: no credentials available")
            return
        }
        let password = WhereWeAre.getPassword() ?? ""
        do {
            if let response = try await getFlux(password: password) {
                await MainActor.run {
                    self.latestResponse = response
                    self.refreshTemplates()
                }
            }
        } catch {
            logger.error("CarPlay: failed to load data: \(error.localizedDescription)")
        }
    }

    @objc private func dataDidUpdate(_ notification: Notification) {
        guard let response = notification.userInfo?["data"] as? LoginResponse else { return }
        latestResponse = response
        refreshTemplates()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.loadInitialData()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let interfaceController else { return }

        let assistantTab = buildAssistantTab()
        let statusTab = buildStatusTab()

        let tabBar = CPTabBarTemplate(templates: [assistantTab, statusTab])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    private func refreshTemplates() {
        guard let interfaceController,
              let tabBar = interfaceController.rootTemplate as? CPTabBarTemplate else { return }

        let assistantTab = assistantTemplate ?? buildAssistantTab()
        let statusTab = buildStatusTab()
        tabBar.updateTemplates([assistantTab, statusTab])
    }

    // MARK: - Assistant tab

    private func buildAssistantTab() -> CPInformationTemplate {
        let button = CPTextButton(
            title: "🎙️ Tap to Speak",
            textStyle: .normal
        ) { [weak self] _ in
            self?.voiceManager?.toggleRecording()
        }

        let template = CPInformationTemplate(
            title: "Assistant",
            layout: .leading,
            items: [
                CPInformationItem(title: nil, detail: "🚫🎙️"),
                CPInformationItem(title: "AI Assistant", detail: "Ready")
            ],
            actions: [button]
        )
        template.tabImage = UIImage(systemName: "mic.circle")
        assistantTemplate = template
        return template
    }

    private func updateAssistantItem(for state: CarPlayVoiceManager.VoiceState) {
        guard let template = assistantTemplate else { return }

        switch state {
        case .idle:
            template.items = [
                CPInformationItem(title: nil, detail: "🚫🎙️"),
                CPInformationItem(title: "AI Assistant", detail: "Ready")
            ]
            let startButton = CPTextButton(
                title: "🎙️ Tap to Speak",
                textStyle: .normal
            ) { [weak self] _ in
                self?.voiceManager?.toggleRecording()
            }
            template.actions = [startButton]

        case .listening:
            template.items = [
                CPInformationItem(title: nil, detail: "🎙️"),
                CPInformationItem(title: "Listening…", detail: "Speak now")
            ]
            let sendButton = CPTextButton(
                title: "📤 Send",
                textStyle: .normal
            ) { [weak self] _ in
                self?.voiceManager?.sendNow()
            }
            let cancelButton = CPTextButton(
                title: "Cancel",
                textStyle: .cancel
            ) { [weak self] _ in
                self?.voiceManager?.toggleRecording()
            }
            template.actions = [sendButton, cancelButton]

        case .thinking:
            template.items = [
                CPInformationItem(title: nil, detail: "🧠"),
                CPInformationItem(title: "Thinking…", detail: "Processing your request")
            ]
            let cancelButton = CPTextButton(
                title: "Cancel",
                textStyle: .cancel
            ) { [weak self] _ in
                self?.voiceManager?.toggleRecording()
            }
            template.actions = [cancelButton]

        case .speaking:
            template.items = [
                CPInformationItem(title: nil, detail: "🔊"),
                CPInformationItem(title: "Speaking…", detail: "Playing response")
            ]
            let stopButton = CPTextButton(
                title: "Stop",
                textStyle: .cancel
            ) { [weak self] _ in
                self?.voiceManager?.toggleRecording()
            }
            template.actions = [stopButton]
        }
    }

    // MARK: - Status tab

    private func buildStatusTab() -> CPListTemplate {
        var sections: [CPListSection] = []

        if let section = buildAppliancesSection() { sections.append(section) }
        if let section = buildRobotsSection() { sections.append(section) }
        if let section = buildVehiclesSection() { sections.append(section) }

        if sections.isEmpty {
            let emptyItem = CPListItem(text: "No data", detailText: "Connect to load status")
            sections.append(CPListSection(items: [emptyItem]))
        }

        let template = CPListTemplate(title: "Status", sections: sections)
        template.tabImage = UIImage(systemName: "house.fill")
        return template
    }

    private func buildAppliancesSection() -> CPListSection? {
        var items: [CPListItem] = []
        if let dishwasher = latestResponse?.dishwasher {
            items.append(CPListItem(
                text: "Dishwasher",
                detailText: dishwasherStatusText(dishwasher),
                image: UIImage(systemName: "dishwasher")
            ))
        }
        if let washer = latestResponse?.washer {
            items.append(CPListItem(
                text: "Washer",
                detailText: washerDryerStatusText(washer),
                image: UIImage(systemName: "washer")
            ))
        }
        if let dryer = latestResponse?.dryer {
            items.append(CPListItem(
                text: "Dryer",
                detailText: washerDryerStatusText(dryer),
                image: UIImage(systemName: "dryer")
            ))
        }
        guard !items.isEmpty else { return nil }
        return CPListSection(items: items, header: "Appliances", sectionIndexTitle: nil)
    }

    private func buildRobotsSection() -> CPListSection? {
        guard let response = latestResponse else { return nil }
        let items = [
            CPListItem(
                text: "BroomBot",
                detailText: robotStatusText(response.broombot),
                image: UIImage(systemName: "fan")
            ),
            CPListItem(
                text: "MopBot",
                detailText: robotStatusText(response.mopbot),
                image: UIImage(systemName: "humidifier.and.droplets")
            )
        ]
        return CPListSection(items: items, header: "Robots", sectionIndexTitle: nil)
    }

    private func buildVehiclesSection() -> CPListSection? {
        var items: [CPListItem] = []
        if let scooter = latestResponse?.scooter {
            items.append(CPListItem(
                text: "Scooter",
                detailText: scooterStatusText(scooter),
                image: UIImage(systemName: "scooter")
            ))
        }
        if let car = latestResponse?.car, let evStatus = latestResponse?.carEvStatus {
            let lockText = car.doorLock ? "Locked" : "Unlocked"
            let range = evStatus.drvDistance.first?.rangeByFuel.evModeRange.value ?? 0
            let carDetail = "\(lockText) · \(evStatus.batteryStatus)% · \(range) km"
            items.append(CPListItem(
                text: "Car",
                detailText: carDetail,
                image: UIImage(systemName: "car.fill")
            ))
            if car.airCtrlOn {
                items.append(CPListItem(
                    text: "Climate",
                    detailText: "On",
                    image: UIImage(systemName: "thermometer.snowflake")
                ))
            }
        }
        guard !items.isEmpty else { return nil }
        return CPListSection(items: items, header: "Vehicles", sectionIndexTitle: nil)
    }

    // MARK: - Status text helpers

    private func robotStatusText(_ robot: Robot) -> String {
        var parts: [String] = []
        if robot.running == true {
            parts.append("Running")
        } else if robot.charging == true {
            parts.append("Charging")
        } else if robot.docking == true {
            parts.append("Docking")
        } else if robot.paused == true {
            parts.append("Paused")
        } else {
            parts.append("Idle")
        }
        if let battery = robot.batteryLevel {
            parts.append("\(battery)%")
        }
        return parts.joined(separator: " · ")
    }

    private func dishwasherStatusText(_ dishwasher: DishWasher) -> String {
        var parts: [String] = []
        parts.append(dishwasher.operationState.rawValue)
        if let program = dishwasher.activeProgram {
            parts.append(program.displayName)
        }
        if let remaining = dishwasher.remainingTime, remaining > 0 {
            parts.append(formatDurationMinutes(remaining / 60))
        }
        return parts.joined(separator: " · ")
    }

    private func washerDryerStatusText(_ device: WasherDryer) -> String {
        var parts: [String] = []
        if device.inUse {
            parts.append("Running")
            if let program = device.programName,
               !program.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(program)
            }
            if let remaining = device.timeRemaining, remaining > 0 {
                parts.append(formatDurationMinutes(remaining))
            }
        } else {
            parts.append(device.status ?? "Idle")
        }
        return parts.joined(separator: " · ")
    }

    private func scooterStatusText(_ scooter: ScooterSummary) -> String {
        var parts: [String] = []
        if let battery = scooter.battery {
            parts.append("\(battery)%")
        }
        if let range = scooter.estimatedRange {
            parts.append("\(Int(range)) km")
        }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }
}
