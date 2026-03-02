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
    var favouriteHomeKit: [String]
    @State private var sceneManager = SceneManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeAppliancesSection
            deviceStatusSection
            scenesSection
            quickActionsSection
            Divider()
            footerSection
        }
        .padding()
        .frame(width: 320)
        .task {
            await sceneManager.loadScenes(favouriteNames: favouriteHomeKit)
        }
    }

    @ViewBuilder
    private var activeAppliancesSection: some View {
        let active = activeAppliances
        if !active.isEmpty {
            Text("Active")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            ForEach(active.indices, id: \.self) { index in
                Button(action: { openAppToSection(.appliances) }, label: {
                    HStack {
                        Image(systemName: applianceIcon(active[index]))
                            .foregroundColor(Theme.Colors.accent)
                        Text(active[index].name)
                            .font(Theme.Fonts.bodySmall)
                        Spacer()
                        if active[index].timeRemaining > 0 {
                            Text("\(active[index].timeRemaining)m left")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        } else {
                            Text("Running")
                                .font(Theme.Fonts.caption)
                                .foregroundColor(Theme.Colors.accent)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
            }
            Divider()
        }
    }

    @ViewBuilder
    private var deviceStatusSection: some View {
        if let car {
            Button(action: { openAppToSection(.car) }, label: {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(Theme.Colors.accent)
                    Text("Car")
                        .font(Theme.Fonts.bodyMedium)
                    Spacer()
                    Text("\(car.vehicle.batteryLevel)%")
                        .font(Theme.Fonts.bodyMedium)
                    Image(systemName: car.vehicle.locked ? "lock.fill" : "lock.open.fill")
                        .foregroundColor(car.vehicle.locked ? Theme.Colors.success : Theme.Colors.warning)
                        .font(.caption)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
        }
        if let robots {
            Button(action: { openAppToSection(.robots) }, label: {
                HStack {
                    Image(systemName: "fan.fill")
                        .foregroundColor(
                            robots.broomBot.running == true ? Theme.Colors.accent : Theme.Colors.textSecondary
                        )
                    Text("BroomBot").font(Theme.Fonts.bodyMedium)
                    Spacer()
                    Text(robotShortStatus(robots.broomBot))
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            Button(action: { openAppToSection(.robots) }, label: {
                HStack {
                    Image(systemName: "humidifier.and.droplets")
                        .foregroundColor(
                            robots.mopBot.running == true ? Theme.Colors.accent : Theme.Colors.textSecondary
                        )
                    Text("MopBot").font(Theme.Fonts.bodyMedium)
                    Spacer()
                    Text(robotShortStatus(robots.mopBot))
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var scenesSection: some View {
        if !sceneManager.favourites.isEmpty {
            Divider()
            Text("Scenes")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            FlowLayout(spacing: 6) {
                ForEach(sceneManager.favourites) { scene in
                    Button(action: {
                        sceneManager.activate(scene, favouriteNames: favouriteHomeKit)
                    }, label: {
                        HStack(spacing: 4) {
                            Image(systemName: scene.isActive == true ? "lightbulb.fill" : "lightbulb")
                                .font(.caption2)
                                .foregroundColor(
                                    scene.isActive == true ? Theme.Colors.accent : Theme.Colors.textSecondary
                                )
                            Text(scene.name)
                                .font(Theme.Fonts.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    })
                    .buttonStyle(.bordered)
                    .tint(scene.isActive == true ? Theme.Colors.accent : nil)
                    .disabled(sceneManager.activatingSceneId != nil)
                }
            }
        }
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        if car != nil || robots != nil {
            Divider()
            Text("Quick Actions")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            HStack(spacing: 8) {
                if let car {
                    Button(action: {
                        car.performAction(
                            action: car.vehicle.locked ? "unlock" : "lock"
                        )
                    }, label: {
                        Label(
                            car.vehicle.locked ? "Unlock Car" : "Lock Car",
                            systemImage: car.vehicle.locked
                                ? "lock.open" : "lock"
                        ).font(Theme.Fonts.caption)
                    })
                    .buttonStyle(.bordered)
                }
                if let robots {
                    Button(action: {
                        robots.performAction(
                            action: "start", robot: "broomBot"
                        )
                    }, label: {
                        Label("Start Vacuum", systemImage: "fan")
                            .font(Theme.Fonts.caption)
                    })
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("Open FluxHaus") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .font(Theme.Fonts.caption)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(Theme.Fonts.caption)
        }
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
        if lower.contains("dryer") || lower.contains("dry") { return "dryer.fill" }
        if lower.contains("oven") { return "oven.fill" }
        return "powerplug.fill"
    }

    private func robotShortStatus(_ robot: Robot) -> String {
        if robot.running == true { return "Running" }
        if robot.charging == true { return "Charging" }
        return "Idle"
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
        favouriteHomeKit: ["Good Morning", "Bedtime"]
    )
}
#endif
