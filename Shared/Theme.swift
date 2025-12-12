//
//  Theme.swift
//  FluxHaus
//
//  Created by Copilot on 2025-12-11.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct Theme {
    // Catppuccin Palette
    private struct CatppuccinLatte {
        static let rosewater = Color(hex: "dc8a78")
        static let flamingo = Color(hex: "dd7878")
        static let pink = Color(hex: "ea76cb")
        static let mauve = Color(hex: "8839ef")
        static let red = Color(hex: "d20f39")
        static let maroon = Color(hex: "e64553")
        static let peach = Color(hex: "fe640b")
        static let yellow = Color(hex: "df8e1d")
        static let green = Color(hex: "40a02b")
        static let teal = Color(hex: "179299")
        static let sky = Color(hex: "04a5e5")
        static let sapphire = Color(hex: "209fb5")
        static let blue = Color(hex: "1e66f5")
        static let lavender = Color(hex: "7287fd")
        static let text = Color(hex: "4c4f69")
        static let subtext1 = Color(hex: "5c5f77")
        static let subtext0 = Color(hex: "6c6f85")
        static let overlay2 = Color(hex: "7c7f93")
        static let overlay1 = Color(hex: "8c8fa1")
        static let overlay0 = Color(hex: "9ca0b0")
        static let surface2 = Color(hex: "acb0be")
        static let surface1 = Color(hex: "bcc0cc")
        static let surface0 = Color(hex: "ccd0da")
        static let base = Color(hex: "eff1f5")
        static let mantle = Color(hex: "e6e9ef")
        static let crust = Color(hex: "dce0e8")
    }

    private struct CatppuccinMocha {
        static let rosewater = Color(hex: "f5e0dc")
        static let flamingo = Color(hex: "f2cdcd")
        static let pink = Color(hex: "f5c2e7")
        static let mauve = Color(hex: "cba6f7")
        static let red = Color(hex: "f38ba8")
        static let maroon = Color(hex: "eba0ac")
        static let peach = Color(hex: "fab387")
        static let yellow = Color(hex: "f9e2af")
        static let green = Color(hex: "a6e3a1")
        static let teal = Color(hex: "94e2d5")
        static let sky = Color(hex: "89dceb")
        static let sapphire = Color(hex: "74c7ec")
        static let blue = Color(hex: "89b4fa")
        static let lavender = Color(hex: "b4befe")
        static let text = Color(hex: "cdd6f4")
        static let subtext1 = Color(hex: "bac2de")
        static let subtext0 = Color(hex: "a6adc8")
        static let overlay2 = Color(hex: "9399b2")
        static let overlay1 = Color(hex: "7f849c")
        static let overlay0 = Color(hex: "6c7086")
        static let surface2 = Color(hex: "585b70")
        static let surface1 = Color(hex: "45475a")
        static let surface0 = Color(hex: "313244")
        static let base = Color(hex: "1e1e2e")
        static let mantle = Color(hex: "181825")
        static let crust = Color(hex: "11111b")
    }

    private static func dynamicColor(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        }))
        #else
        return light
        #endif
    }

    public struct Colors {
        // Accent Color: Peach
        public static let accent = dynamicColor(light: CatppuccinLatte.peach, dark: CatppuccinMocha.peach)

        // Primary Color: Mauve
        public static let primary = dynamicColor(light: CatppuccinLatte.mauve, dark: CatppuccinMocha.mauve)

        // Secondary Color: Teal
        public static let secondary = dynamicColor(light: CatppuccinLatte.teal, dark: CatppuccinMocha.teal)

        // Background Colors
        public static let background = dynamicColor(light: CatppuccinLatte.base, dark: CatppuccinMocha.base)
        public static let secondaryBackground = dynamicColor(
            light: CatppuccinLatte.mantle,
            dark: CatppuccinMocha.mantle
        )

        // Text Colors
        public static var textPrimary: Color {
            #if os(visionOS)
            return .primary
            #else
            return dynamicColor(light: CatppuccinLatte.text, dark: CatppuccinMocha.text)
            #endif
        }

        public static var textSecondary: Color {
            #if os(visionOS)
            return .secondary
            #else
            return dynamicColor(
                light: CatppuccinLatte.subtext0,
                dark: CatppuccinMocha.subtext0
            )
            #endif
        }

        // Alert Colors
        public static let error = dynamicColor(light: CatppuccinLatte.red, dark: CatppuccinMocha.red)
        public static let warning = dynamicColor(light: CatppuccinLatte.yellow, dark: CatppuccinMocha.yellow)
        public static let success = dynamicColor(light: CatppuccinLatte.green, dark: CatppuccinMocha.green)
        public static let info = dynamicColor(light: CatppuccinLatte.blue, dark: CatppuccinMocha.blue)
    }

    public struct Fonts {
        // Headers: Serif font (New York on Apple platforms)
        public static func header4XL() -> Font {
            return .custom("New York", size: 72).weight(.bold)
        }

        public static func headerXL() -> Font {
            return .custom("New York", size: 36).weight(.bold)
        }

        public static func headerLarge() -> Font {
            return .custom("New York", size: 24).weight(.bold)
        }

        // Body Text: System default (SF Pro)
        public static let bodyLarge = Font.system(size: 18)
        public static let bodyMedium = Font.system(size: 16)
        public static let bodySmall = Font.system(size: 14)
        public static let caption = Font.caption
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha, red, green, blue: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
