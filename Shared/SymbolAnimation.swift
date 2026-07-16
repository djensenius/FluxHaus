//
//  SymbolAnimation.swift
//  FluxHaus
//
//  Central helpers for animating SF Symbols on device icons.
//

import SwiftUI

/// Testing switch: when `true`, every animatable device symbol animates
/// regardless of whether the underlying device is active. Flip to `false`
/// so symbols only animate when their device is actually on/running.
enum SymbolAnimationTesting {
    static let forceAll = false
}

/// Logical animation styles mapped to device behaviour.
enum DeviceSymbolAnimation {
    /// Spinning motion — robot vacuum, laundry drum, etc.
    case rotate
    /// Gentle pulse — vehicles preparing/charging.
    case pulse
    /// Flowing colour — water/moisture (mop) devices.
    case variableColor
    /// Breathing scale — air moving through a purifier.
    case breathe
    /// Vibration — a running machine.
    case wiggle
}

private struct DeviceSymbolAnimationModifier: ViewModifier {
    let animation: DeviceSymbolAnimation
    let isActive: Bool

    private var active: Bool { isActive || SymbolAnimationTesting.forceAll }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch animation {
        case .rotate:
            content.symbolEffect(.rotate, options: .repeating, isActive: active)
        case .pulse:
            content.symbolEffect(.pulse, options: .repeating, isActive: active)
        case .variableColor:
            content.symbolEffect(.variableColor, options: .repeating, isActive: active)
        case .breathe:
            content.symbolEffect(.breathe, options: .repeating, isActive: active)
        case .wiggle:
            content.symbolEffect(.wiggle, options: .repeating, isActive: active)
        }
    }
}

extension View {
    /// Applies a repeating SF Symbol effect while the device is active (or
    /// always, when `SymbolAnimationTesting.forceAll` is enabled). Passing a
    /// `nil` animation leaves the view untouched.
    @ViewBuilder
    func deviceSymbolAnimation(_ animation: DeviceSymbolAnimation?, isActive: Bool) -> some View {
        if let animation {
            modifier(DeviceSymbolAnimationModifier(animation: animation, isActive: isActive))
        } else {
            self
        }
    }
}
