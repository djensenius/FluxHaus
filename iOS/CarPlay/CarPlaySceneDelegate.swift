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
    private var assistantItem: CPListItem?

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

        let assistantTab = buildAssistantTab()
        let statusTab = buildStatusTab()
        tabBar.updateTemplates([assistantTab, statusTab])
    }

    // MARK: - Assistant tab

    private func buildAssistantTab() -> CPListTemplate {
        let item = CPListItem(
            text: "Tap to Speak",
            detailText: "Talk to your AI assistant",
            image: UIImage(systemName: "mic.circle")
        )
        item.handler = { [weak self] _, completion in
            self?.voiceManager?.toggleRecording()
            completion()
        }
        assistantItem = item

        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Assistant", sections: [section])
        template.tabImage = UIImage(systemName: "mic.circle")
        return template
    }

    private func updateAssistantItem(for state: CarPlayVoiceManager.VoiceState) {
        guard let item = assistantItem else { return }
        switch state {
        case .idle:
            item.setText("Tap to Speak")
            item.setDetailText("Talk to your AI assistant")
            item.setImage(UIImage(systemName: "mic.circle"))
        case .listening:
            item.setText("Listening…")
            item.setDetailText("Tap to cancel")
            item.setImage(UIImage(systemName: "mic.fill"))
        case .thinking:
            item.setText("Thinking…")
            item.setDetailText("Processing your request")
            item.setImage(UIImage(systemName: "brain"))
        case .speaking:
            item.setText("Speaking…")
            item.setDetailText("Tap to stop")
            item.setImage(UIImage(systemName: "speaker.wave.2.fill"))
        }
    }

    // MARK: - Status tab

    private func buildStatusTab() -> CPListTemplate {
        var sections: [CPListSection] = []

        // Appliances section (dishwasher, washer, dryer — same order as iOS home)
        var applianceItems: [CPListItem] = []
        if let dishwasher = latestResponse?.dishwasher {
            let status = dishwasherStatusText(dishwasher)
            let item = CPListItem(
                text: "Dishwasher",
                detailText: status,
                image: UIImage(systemName: "dishwasher")
            )
            applianceItems.append(item)
        }
        if let washer = latestResponse?.washer {
            let status = washerDryerStatusText(washer)
            let item = CPListItem(
                text: "Washer",
                detailText: status,
                image: UIImage(systemName: "washer")
            )
            applianceItems.append(item)
        }
        if let dryer = latestResponse?.dryer {
            let status = washerDryerStatusText(dryer)
            let item = CPListItem(
                text: "Dryer",
                detailText: status,
                image: UIImage(systemName: "dryer")
            )
            applianceItems.append(item)
        }
        if !applianceItems.isEmpty {
            sections.append(CPListSection(items: applianceItems, header: "Appliances", sectionIndexTitle: nil))
        }

        // Robots section
        var robotItems: [CPListItem] = []
        if let response = latestResponse {
            let broomStatus = robotStatusText(response.broombot)
            let broomItem = CPListItem(
                text: "BroomBot",
                detailText: broomStatus,
                image: UIImage(systemName: "fan")
            )
            robotItems.append(broomItem)

            let mopStatus = robotStatusText(response.mopbot)
            let mopItem = CPListItem(
                text: "MopBot",
                detailText: mopStatus,
                image: UIImage(systemName: "humidifier.and.droplets")
            )
            robotItems.append(mopItem)
        }
        if !robotItems.isEmpty {
            sections.append(CPListSection(items: robotItems, header: "Robots", sectionIndexTitle: nil))
        }

        // Car section
        if let car = latestResponse?.car, let evStatus = latestResponse?.carEvStatus {
            var carItems: [CPListItem] = []
            let lockText = car.doorLock ? "Locked" : "Unlocked"
            let range = evStatus.drvDistance.first?.rangeByFuel.evModeRange.value ?? 0
            let carDetail = "\(lockText) · \(evStatus.batteryStatus)% · \(range) km"
            let lockItem = CPListItem(
                text: "Car",
                detailText: carDetail,
                image: UIImage(systemName: "car.fill")
            )
            carItems.append(lockItem)

            if car.airCtrlOn {
                let climateItem = CPListItem(
                    text: "Climate",
                    detailText: "On",
                    image: UIImage(systemName: "thermometer.snowflake")
                )
                carItems.append(climateItem)
            }
            sections.append(CPListSection(items: carItems, header: "Car", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            let emptyItem = CPListItem(text: "No data", detailText: "Connect to load status")
            sections.append(CPListSection(items: [emptyItem]))
        }

        let template = CPListTemplate(title: "Status", sections: sections)
        template.tabImage = UIImage(systemName: "house.fill")
        return template
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
}
