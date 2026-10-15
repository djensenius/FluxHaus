//
//  CarPlaySceneDelegate.swift
//  FluxHaus
//
//  Created by David Jensenius on 2026-04-18.
//

import CarPlay
import os

private let logger = Logger(subsystem: "io.fluxhaus.FluxHaus", category: "CarPlay")

@MainActor
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var voiceManager: CarPlayVoiceManager?
    private var latestResponse: LoginResponse?
    private var refreshTimer: Timer?
    private var assistantTemplate: CPListTemplate?
    private var assistantItem: CPListItem?
    private var scenesTemplate: CPListTemplate?
    private var scenes: [HomeScene] = []
    private var scenesState: ScenesState = .loading
    /// Auth session the displayed scenes (and their handlers) belong to.
    private var scenesSession: String?

    private enum ScenesState {
        case loading
        case loaded
        case failed
    }

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(authDidSignOut(_:)),
            name: .authDidSignOut, object: nil
        )

        voiceManager = CarPlayVoiceManager()
        voiceManager?.onStateChange = { [weak self] state in
            self?.updateAssistantItem(for: state)
        }

        Task {
            await loadInitialData()
            await MainActor.run { buildUI() }
            await loadScenes()
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
        let session = AuthManager.shared.widgetSessionID()
        do {
            if let response = try await getFlux(password: password),
               session != nil, AuthManager.shared.widgetSessionID() == session {
                await MainActor.run {
                    self.latestResponse = response
                    self.refreshTemplates()
                }
            }
        } catch {
            logger.error("CarPlay: failed to load data: \(error.localizedDescription)")
        }
    }

    @objc private func authDidSignOut(_ notification: Notification) {
        // Never keep showing (or acting on) the previous account's data.
        latestResponse = nil
        scenes = []
        scenesSession = nil
        scenesState = .loading
        scenesTemplate?.updateSections(sceneSections())
        refreshTemplates()
    }

    @objc private func dataDidUpdate(_ notification: Notification) {
        guard let response = notification.userInfo?["data"] as? LoginResponse else { return }
        latestResponse = response
        refreshTemplates()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadInitialData()
                // Keep scenes current (active state, additions, account changes, retries).
                await self?.loadScenes()
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
        let scenesTab = buildScenesTab()

        let tabBar = CPTabBarTemplate(templates: [assistantTab, statusTab, scenesTab])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    private func refreshTemplates() {
        guard let interfaceController,
              let tabBar = interfaceController.rootTemplate as? CPTabBarTemplate else { return }

        let assistantTab = assistantTemplate ?? buildAssistantTab()
        let statusTab = buildStatusTab()
        let scenesTab = scenesTemplate ?? buildScenesTab()
        tabBar.updateTemplates([assistantTab, statusTab, scenesTab])
    }

    // MARK: - Assistant tab

    private func buildAssistantTab() -> CPListTemplate {
        let item = CPListItem(
            text: "Tap to Speak",
            detailText: "Talk to your AI assistant",
            image: UIImage(systemName: "mic.slash")
        )
        item.handler = { [weak self] _, completion in
            self?.voiceManager?.toggleRecording()
            completion()
        }
        assistantItem = item

        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Assistant", sections: [section])
        template.tabImage = UIImage(systemName: "mic.circle")
        assistantTemplate = template
        return template
    }

    private func updateAssistantItem(for state: CarPlayVoiceManager.VoiceState) {
        guard let item = assistantItem else { return }

        switch state {
        case .idle:
            item.setText("Tap to Speak")
            item.setDetailText("Talk to your AI assistant")
            item.setImage(UIImage(systemName: "mic.slash"))
            updateAssistantActions(showSend: false)

        case .listening:
            item.setText("Listening…")
            item.setDetailText("Speak now")
            item.setImage(UIImage(systemName: "mic.fill"))
            updateAssistantActions(showSend: true)

        case .thinking:
            item.setText("Thinking…")
            item.setDetailText("Processing your request")
            item.setImage(UIImage(systemName: "brain"))
            updateAssistantActions(showSend: false)

        case .speaking:
            item.setText("Speaking…")
            item.setDetailText("Playing response")
            item.setImage(UIImage(systemName: "speaker.wave.2.fill"))
            updateAssistantActions(showSend: false)
        }
    }

    private func updateAssistantActions(showSend: Bool) {
        guard let template = assistantTemplate else { return }
        if showSend {
            let send = CPListItem(
                text: "Send",
                detailText: "Stop recording and send",
                image: UIImage(systemName: "arrow.up.circle.fill")
            )
            send.handler = { [weak self] _, completion in
                self?.voiceManager?.sendNow()
                completion()
            }
            let cancel = CPListItem(
                text: "Cancel",
                detailText: "Stop recording",
                image: UIImage(systemName: "xmark.circle")
            )
            cancel.handler = { [weak self] _, completion in
                self?.voiceManager?.toggleRecording()
                completion()
            }
            template.updateSections([
                CPListSection(items: [assistantItem, send, cancel].compactMap { $0 })
            ])
        } else {
            template.updateSections([
                CPListSection(items: [assistantItem].compactMap { $0 })
            ])
        }
    }

    // MARK: - Scenes tab

    private func loadScenes() async {
        guard let session = AuthManager.shared.widgetSessionID() else {
            scenes = []
            scenesSession = nil
            scenesState = .loading
            scenesTemplate?.updateSections(sceneSections())
            return
        }
        do {
            let fetched = try await fetchScenes()
            // Discard results from a request that started under a different account.
            guard AuthManager.shared.widgetSessionID() == session else { return }
            scenes = fetched
            scenesSession = session
            scenesState = .loaded
        } catch {
            logger.error("CarPlay: failed to load scenes: \(error.localizedDescription)")
            guard AuthManager.shared.widgetSessionID() == session else { return }
            if scenesSession != session { scenes = [] }
            scenesState = scenes.isEmpty ? .failed : .loaded
        }
        scenesTemplate?.updateSections(sceneSections())
    }

    private func buildScenesTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Scenes", sections: sceneSections())
        template.tabImage = UIImage(systemName: "lightbulb.fill")
        scenesTemplate = template
        return template
    }

    private func sceneSections() -> [CPListSection] {
        guard !scenes.isEmpty else {
            let item: CPListItem
            switch scenesState {
            case .loading:
                item = CPListItem(text: "Loading scenes…", detailText: nil)
            case .failed:
                item = CPListItem(text: "Couldn't load scenes", detailText: "Tap to retry")
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        self?.scenesState = .loading
                        self?.scenesTemplate?.updateSections(self?.sceneSections() ?? [])
                        await self?.loadScenes()
                        completion()
                    }
                }
            case .loaded:
                item = CPListItem(text: "No scenes", detailText: "Add scenes in Home Assistant")
            }
            return [CPListSection(items: [item])]
        }
        let items = scenes.map { scene in
            let item = CPListItem(
                text: scene.name,
                detailText: scene.isActive == true ? "Active" : nil,
                image: UIImage(systemName: "lightbulb.fill")
            )
            let session = scenesSession
            item.handler = { [weak item] _, completion in
                Task { @MainActor in
                    guard session != nil, AuthManager.shared.widgetSessionID() == session else {
                        item?.setDetailText("Signed out")
                        completion()
                        return
                    }
                    item?.setDetailText("Activating…")
                    do {
                        try await activateScene(entityId: scene.entityId)
                        item?.setDetailText("Activated")
                    } catch {
                        item?.setDetailText("Couldn't activate")
                    }
                    completion()
                }
            }
            return item
        }
        return [CPListSection(items: items)]
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
                text: "Cleanbot",
                detailText: robotStatusText(response.cleanbot),
                image: UIImage(systemName: "robotic.vacuum.fill")
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
        parts.append(dishwasher.operationState.displayText)
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
                parts.append(formatApplianceDisplayText(program))
            }
            if let remaining = device.timeRemaining, remaining > 0 {
                parts.append(formatDurationMinutes(remaining))
            }
        } else {
            parts.append(device.status.map { formatApplianceDisplayText($0) } ?? "Idle")
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
