//
//  MenuBarView.swift
//  FluxHaus (macOS)
//
//  Created by Copilot on 2026-03-02.
//

import SwiftUI

struct MenuBarView: View {
    var car: Car?
    var robots: Robots?
    var miele: Miele?
    var hconn: HomeConnect?
    var favouriteScenes: [String]
    @State private var sceneManager = SceneManager()
    @ObservedObject private var authManager = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            activeAppliancesSection
            deviceStatusSection
            scenesSection
            quickActionsSection
            Divider().padding(.vertical, 4)
            footerSection
        }
        .padding(10)
        .frame(width: 300)
        .task {
            await sceneManager.loadScenes(favouriteNames: favouriteScenes)
        }
    }

    @ViewBuilder
    private var activeAppliancesSection: some View {
        let active = activeAppliances
        if !active.isEmpty {
            sectionHeader("Active")
            ForEach(active.indices, id: \.self) { index in
                menuRow(action: {
                    dismiss()
                    openAppToSection(.appliances)
                }, label: {
                    HStack {
                        Image(systemName: applianceIcon(active[index]))
                            .foregroundColor(Theme.Colors.accent)
                            .frame(width: 16)
                        Text(active[index].name)
                            .font(Theme.Fonts.bodySmall)
                        Spacer()
                        if active[index].timeRemaining > 0 {
                            Text("\(active[index].timeRemaining)m")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        } else {
                            Text("Running")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        }
                    }
                })
            }
            Divider().padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var deviceStatusSection: some View {
        if let car {
            menuRow(action: {
                dismiss()
                openAppToSection(.car)
            }, label: {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 16)
                    Text("Car").font(Theme.Fonts.bodySmall)
                    Spacer()
                    Text("\(car.vehicle.batteryLevel)%")
                        .font(Theme.Fonts.bodySmall)
                    Image(
                        systemName: car.vehicle.locked
                            ? "lock.fill" : "lock.open.fill"
                    )
                    .foregroundColor(
                        car.vehicle.locked
                            ? Theme.Colors.success
                            : Theme.Colors.warning
                    )
                    .font(Theme.Fonts.caption)
                }
            })
        }
        if let robots {
            menuRow(action: {
                dismiss()
                openAppToSection(.robots)
            }, label: {
                HStack {
                    Image(systemName: "fan.fill")
                        .foregroundColor(
                            robots.broomBot.running == true
                                ? Theme.Colors.accent
                                : Theme.Colors.textSecondary
                        )
                        .frame(width: 16)
                    Text("BroomBot").font(Theme.Fonts.bodySmall)
                    Spacer()
                    Text(robotShortStatus(robots.broomBot))
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            })
            menuRow(action: {
                dismiss()
                openAppToSection(.robots)
            }, label: {
                HStack {
                    Image(systemName: "humidifier.and.droplets")
                        .foregroundColor(
                            robots.mopBot.running == true
                                ? Theme.Colors.accent
                                : Theme.Colors.textSecondary
                        )
                        .frame(width: 16)
                    Text("MopBot").font(Theme.Fonts.bodySmall)
                    Spacer()
                    Text(robotShortStatus(robots.mopBot))
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            })
        }
    }

    @ViewBuilder
    private var scenesSection: some View {
        if !sceneManager.favourites.isEmpty {
            Divider().padding(.vertical, 4)
            sectionHeader("Scenes")
            FlowLayout(spacing: 6) {
                ForEach(sceneManager.favourites) { scene in
                    Button(action: {
                        sceneManager.activate(
                            scene, favouriteNames: favouriteScenes
                        )
                    }, label: {
                        HStack(spacing: 4) {
                            Image(
                                systemName: scene.isActive == true
                                    ? "lightbulb.fill" : "lightbulb"
                            )
                            .font(.caption2)
                            .foregroundColor(
                                scene.isActive == true
                                    ? Theme.Colors.accent
                                    : Theme.Colors.textSecondary
                            )
                            Text(scene.name)
                                .font(Theme.Fonts.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    })
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(
                        scene.isActive == true
                            ? Theme.Colors.accent : nil
                    )
                    .disabled(sceneManager.activatingSceneId != nil)
                }
            }
        }
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        if car != nil || robots != nil {
            Divider().padding(.vertical, 4)
            sectionHeader("Quick Actions")
            FlowLayout(spacing: 6) {
                if let car {
                    quickButton(
                        car.vehicle.locked ? "Unlock Car" : "Lock Car",
                        icon: car.vehicle.locked
                            ? "lock.open" : "lock"
                    ) {
                        car.performAction(
                            action: car.vehicle.locked
                                ? "unlock" : "lock"
                        )
                    }
                    quickButton("Climate", icon: "thermometer.sun") {
                        car.performAction(action: "start")
                    }
                }
                if robots != nil {
                    quickButton("Vacuum", icon: "fan") {
                        robots?.performAction(
                            action: "start", robot: "broomBot"
                        )
                    }
                    quickButton("Deep Clean", icon: "sparkles") {
                        robots?.performAction(
                            action: "deepClean", robot: "broomBot"
                        )
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Open FluxHaus") {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
            }
            .font(Theme.Fonts.caption)
            Spacer()
            if authManager.isOIDC {
                Button(action: {
                    dismiss()
                    NotificationCenter.default.post(name: .quickChatRequested, object: nil)
                }, label: {
                    Label("Quick Chat", systemImage: "bubble.left.and.bubble.right.fill")
                })
                .font(Theme.Fonts.caption)
            }
            Spacer()
            Button("Quit Fully") {
                dismiss()
                NotificationCenter.default.post(name: .fullQuitRequested, object: nil)
            }
            .font(Theme.Fonts.caption)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.caption)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
    }

    private func menuRow<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action, label: label)
            .buttonStyle(MenuRowButtonStyle())
    }

    private func quickButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action, label: {
            Label(title, systemImage: icon)
                .font(Theme.Fonts.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        })
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func openAppToSection(_ section: SidebarItem) {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: Notification.Name("navigateToSection"),
            object: nil,
            userInfo: ["section": section.rawValue]
        )
    }

    private var activeAppliances: [Appliance] {
        var result: [Appliance] = []
        if let hconn {
            result.append(contentsOf: hconn.appliances.filter { $0.inUse })
        }
        if let miele {
            result.append(contentsOf: miele.appliances.filter { $0.inUse })
        }
        return result
    }

    private func applianceIcon(_ appliance: Appliance) -> String {
        let lower = appliance.name.lowercased()
        if lower.contains("dish") { return "dishwasher.fill" }
        if lower.contains("wash") { return "washer.fill" }
        if lower.contains("dryer") || lower.contains("dry") {
            return "dryer.fill"
        }
        if lower.contains("oven") { return "oven.fill" }
        return "powerplug.fill"
    }

    private func robotShortStatus(_ robot: Robot) -> String {
        if robot.running == true { return "Running" }
        if robot.charging == true { return "Charging" }
        return "Idle"
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                configuration.isPressed
                    ? Theme.Colors.accent.opacity(0.2)
                    : Color.clear
            )
            .background(MenuRowHover())
            .cornerRadius(4)
            .contentShape(Rectangle())
    }
}

struct MenuRowHover: NSViewRepresentable {
    func makeNSView(context: Context) -> MenuRowHoverView {
        MenuRowHoverView()
    }
    func updateNSView(_ nsView: MenuRowHoverView, context: Context) {}
}

class MenuRowHoverView: NSView {
    var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        superview?.layer?.backgroundColor = NSColor(
            Theme.Colors.accent.opacity(0.1)
        ).cgColor
        superview?.layer?.cornerRadius = 4
    }

    override func mouseExited(with event: NSEvent) {
        superview?.layer?.backgroundColor = nil
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = arrangeSubviews(
            proposal: proposal, subviews: subviews
        )
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrangeSubviews(
            proposal: proposal, subviews: subviews
        )
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalSize: CGSize = .zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalSize.width = max(totalSize.width, currentX - spacing)
            totalSize.height = max(totalSize.height, currentY + lineHeight)
        }
        return (positions, totalSize)
    }
}

#if DEBUG
#Preview {
    MenuBarView(
        car: MockData.createCar(),
        robots: MockData.createRobots(),
        miele: MockData.createMiele(),
        hconn: MockData.createHomeConnect(),
        favouriteScenes: ["Good Morning", "Bedtime"]
    )
}
#endif
