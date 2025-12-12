//
//  Theme.swift
//  FluxHaus
//
//  Created by Copilot on 2025-12-11.
//

import SwiftUI

public struct Theme {
    public struct Colors {
        // Accent Color: Warm orange
        public static let accent = Color(hex: "EF8A13")

        // Primary Color: Vibrant purple
        public static let primary = Color(hex: "4F4FFF")

        // Secondary Color: Bright cyan
        public static let secondary = Color(hex: "00FBCE")

        // Background Colors
        public static let background = Color("BackgroundColor") // Asset catalog color or system
        public static let secondaryBackground = Color("SecondaryBackgroundColor")

        // Text Colors
        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary

        // Alert Colors
        public static let error = Color.red
        public static let warning = Color.orange
        public static let success = Color.green
        public static let info = Color.blue
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
