//
//  ColorScheme.swift
//  Usage4Claude
//
//  Created by Claude on 2025-11-26.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit
import OSLog

/// Unified color scheme management
/// Provides color configurations for 5-hour and 7-day limits, supporting both AppKit and SwiftUI
enum UsageColorScheme {

    // MARK: - Appearance Detection

    /// Detect whether the current appearance is dark mode
    /// - Parameter statusButton: Optional status bar button used to obtain appearance information
    /// - Returns: true for dark mode, false for light mode
    static func isDarkMode(for statusButton: NSStatusBarButton? = nil) -> Bool {
        // Method 1: Use the status bar button's appearance (most accurate, reflects the actual system menu bar appearance)
        if let button = statusButton,
           let appearance = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return appearance == .darkAqua
        }

        // Method 2: Directly read system appearance settings (unaffected by NSApp.appearance)
        // When the user has set an app appearance preference, NSApp.effectiveAppearance reflects the app setting, not the system setting
        // Menu bar icon rendering must always follow the system appearance, so we detect the actual system state here
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Detect whether the current appearance is dark mode (convenience property)
    static var isDarkMode: Bool {
        return isDarkMode(for: nil)
    }

    // MARK: - 5-Hour Limit Colors (Green -> Orange -> Red)

    /// Returns an NSColor based on 5-hour limit usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: 0-70% green (safe), 70-90% orange (warning), 90-100% red (danger)
    static func fiveHourColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 40/255.0, green: 180/255.0, blue: 70/255.0, alpha: 1.0)  // Slightly dark green #28B446
        } else if percentage < 90 {
            return NSColor.systemOrange
        } else {
            return NSColor.systemRed
        }
    }

    /// Returns a SwiftUI Color based on 5-hour limit usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: 0-70% green (safe), 70-90% orange (warning), 90-100% red (danger)
    ///         Opacity is applied when used in the detail view for softer colors
    static func fiveHourColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return .green.opacity(opacity)  // System green
        } else if percentage < 90 {
            return .orange.opacity(opacity)
        } else {
            return .red.opacity(opacity)
        }
    }

    /// Returns an adaptive NSColor based on 5-hour limit usage percentage (adjusts brightness based on system appearance)
    /// - Parameters:
    ///   - percentage: Usage percentage (0-100)
    ///   - statusButton: Status bar button used to obtain the accurate appearance
    /// - Returns: Status color adapted to the current appearance
    /// - Note: Brightness is automatically increased in dark mode to ensure visibility against dark backgrounds
    static func fiveHourColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = fiveHourColor(percentage)

        if isDarkMode(for: statusButton) {
            // Dark mode: increase brightness to make colors more vivid
            return baseColor.adjustedForDarkMode()
        } else {
            // Light mode: use original color or slightly darker
            return baseColor
        }
    }

    // MARK: - 7-Day Limit Colors

    /// Returns an NSColor based on 7-day limit usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: Current scheme - light purple -> deep purple -> dark magenta
    ///         0-70% light purple (safe), 70-90% deep purple (warning), 90-100% dark magenta (danger)
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 192/255.0, green: 132/255.0, blue: 252/255.0, alpha: 1.0)  // Light purple #C084FC
        } else if percentage < 90 {
            return NSColor(red: 180/255.0, green: 80/255.0, blue: 240/255.0, alpha: 1.0)  // Deep purple #B450F0
        } else {
            return NSColor(red: 180/255.0, green: 30/255.0, blue: 160/255.0, alpha: 1.0)   // Dark magenta #B41EA0 (rich warning)
        }
    }

    /// Returns a SwiftUI Color based on 7-day limit usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: Current scheme - light purple -> deep purple -> dark magenta
    ///         0-70% light purple (safe), 70-90% deep purple (warning), 90-100% dark magenta (danger)
    ///         Opacity is applied when used in the detail view for softer colors
    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.9) -> Color {
        if percentage < 70 {
            return Color(red: 192/255.0, green: 132/255.0, blue: 252/255.0).opacity(opacity)  // Light purple #C084FC
        } else if percentage < 90 {
            return Color(red: 180/255.0, green: 80/255.0, blue: 240/255.0).opacity(opacity)  // Deep purple #B450F0
        } else {
            return Color(red: 180/255.0, green: 30/255.0, blue: 160/255.0).opacity(opacity)   // Dark magenta #B41EA0 (rich warning)
        }
    }

    /// Returns an adaptive NSColor based on 7-day limit usage percentage (adjusts brightness based on system appearance)
    /// - Parameters:
    ///   - percentage: Usage percentage (0-100)
    ///   - statusButton: Status bar button used to obtain the accurate appearance
    /// - Returns: Status color adapted to the current appearance
    /// - Note: Brightness and saturation are automatically increased in dark mode to ensure visibility against dark backgrounds
    static func sevenDayColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = sevenDayColor(percentage)

        if isDarkMode(for: statusButton) {
            // Dark mode: increase brightness and saturation
            return baseColor.adjustedForDarkMode()
        } else {
            // Light mode: use original color
            return baseColor
        }
    }

    // MARK: - Extra Usage Colors (Pink -> Rose -> Magenta)

    /// Returns an NSColor based on Extra Usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: 0-70% pink (safe), 70-90% rose (warning), 90-100% magenta (danger)
    static func extraUsageColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 255/255.0, green: 158/255.0, blue: 205/255.0, alpha: 1.0)  // Pink #FF9ECD
        } else if percentage < 90 {
            return NSColor(red: 236/255.0, green: 72/255.0, blue: 153/255.0, alpha: 1.0)   // Rose #EC4899
        } else {
            return NSColor(red: 217/255.0, green: 70/255.0, blue: 239/255.0, alpha: 1.0)   // Magenta #D946EF
        }
    }

    /// Returns an adaptive NSColor based on Extra Usage percentage
    static func extraUsageColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = extraUsageColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Opus Weekly Colors (Light Orange -> Orange -> Orange-Red)

    /// Returns an NSColor based on Opus Weekly usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: 0-70% amber (safe), 70-90% orange (warning), 90-100% orange-red (danger)
    static func opusWeeklyColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 251/255.0, green: 191/255.0, blue: 36/255.0, alpha: 1.0)  // Amber #FBBF24
        } else if percentage < 90 {
            return NSColor.systemOrange
        } else {
            return NSColor(red: 255/255.0, green: 100/255.0, blue: 50/255.0, alpha: 1.0)   // Orange-red #FF6432
        }
    }

    /// Returns an adaptive NSColor based on Opus Weekly usage percentage
    static func opusWeeklyColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = opusWeeklyColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Sonnet Weekly Colors (Light Blue -> Blue -> Indigo)

    /// Returns an NSColor based on Sonnet Weekly usage percentage
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Corresponding status color
    /// - Note: 0-70% light blue (safe), 70-90% blue (warning), 90-100% deep indigo (danger)
    static func sonnetWeeklyColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 100/255.0, green: 200/255.0, blue: 255/255.0, alpha: 1.0)  // Light blue #64C8FF
        } else if percentage < 90 {
            return NSColor.systemBlue
        } else {
            return NSColor(red: 79/255.0, green: 70/255.0, blue: 229/255.0, alpha: 1.0)   // Deep indigo #4F46E5
        }
    }

    /// Returns an adaptive NSColor based on Sonnet Weekly usage percentage
    static func sonnetWeeklyColorAdaptive(_ percentage: Double, for statusButton: NSStatusBarButton? = nil) -> NSColor {
        let baseColor = sonnetWeeklyColor(percentage)
        if isDarkMode(for: statusButton) {
            return baseColor.adjustedForDarkMode()
        } else {
            return baseColor
        }
    }

    // MARK: - Alternative Color Schemes (comments preserved for easy switching and testing)

    /*
    // Scheme 2: Pink -> Magenta -> Deep magenta
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 255/255.0, green: 158/255.0, blue: 205/255.0, alpha: 1.0)  // Pink #FF9ECD
        } else if percentage < 90 {
            return NSColor(red: 217/255.0, green: 70/255.0, blue: 239/255.0, alpha: 1.0)  // Magenta #D946EF
        } else {
            return NSColor(red: 168/255.0, green: 85/255.0, blue: 247/255.0, alpha: 1.0)   // Deep magenta #A855F7
        }
    }

    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.7) -> Color {
        if percentage < 70 {
            return Color(red: 255/255.0, green: 158/255.0, blue: 205/255.0).opacity(opacity)  // Pink #FF9ECD
        } else if percentage < 90 {
            return Color(red: 217/255.0, green: 70/255.0, blue: 239/255.0).opacity(opacity)  // Magenta #D946EF
        } else {
            return Color(red: 168/255.0, green: 85/255.0, blue: 247/255.0).opacity(opacity)   // Deep magenta #A855F7
        }
    }
    */

    /*
    // Scheme 3: Mint green -> Periwinkle -> Indigo
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 107/255.0, green: 237/255.0, blue: 227/255.0, alpha: 1.0)  // Mint green #6BEDE3
        } else if percentage < 90 {
            return NSColor(red: 129/255.0, green: 140/255.0, blue: 248/255.0, alpha: 1.0)  // Periwinkle #818CF8
        } else {
            return NSColor(red: 76/255.0, green: 81/255.0, blue: 191/255.0, alpha: 1.0)   // Indigo #4C51BF
        }
    }

    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.7) -> Color {
        if percentage < 70 {
            return Color(red: 107/255.0, green: 237/255.0, blue: 227/255.0).opacity(opacity)  // Mint green #6BEDE3
        } else if percentage < 90 {
            return Color(red: 129/255.0, green: 140/255.0, blue: 248/255.0).opacity(opacity)  // Periwinkle #818CF8
        } else {
            return Color(red: 76/255.0, green: 81/255.0, blue: 191/255.0).opacity(opacity)   // Indigo #4C51BF
        }
    }
    */

    /*
    // Scheme 4: Amber -> Orange-purple -> Deep purple
    static func sevenDayColor(_ percentage: Double) -> NSColor {
        if percentage < 70 {
            return NSColor(red: 251/255.0, green: 191/255.0, blue: 36/255.0, alpha: 1.0)  // Amber #FBBF24
        } else if percentage < 90 {
            return NSColor(red: 192/255.0, green: 132/255.0, blue: 252/255.0, alpha: 1.0)  // Orange-purple #C084FC
        } else {
            return NSColor(red: 124/255.0, green: 58/255.0, blue: 237/255.0, alpha: 1.0)   // Deep purple #7C3AED
        }
    }

    static func sevenDayColorSwiftUI(_ percentage: Double, opacity: Double = 0.7) -> Color {
        if percentage < 70 {
            return Color(red: 251/255.0, green: 191/255.0, blue: 36/255.0).opacity(opacity)  // Amber #FBBF24
        } else if percentage < 90 {
            return Color(red: 192/255.0, green: 132/255.0, blue: 252/255.0).opacity(opacity)  // Orange-purple #C084FC
        } else {
            return Color(red: 124/255.0, green: 58/255.0, blue: 237/255.0).opacity(opacity)   // Deep purple #7C3AED
        }
    }
    */
}

// MARK: - NSColor Extension

extension NSColor {
    /// Adjust color for dark mode (increase brightness and saturation)
    /// - Returns: A brighter version suitable for display on dark backgrounds
    func adjustedForDarkMode() -> NSColor {
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            return self
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Increase brightness: ensure minimum brightness of 0.75, up to 40% boost (raised from 0.7/1.3 to 0.75/1.4)
        let adjustedBrightness = min(1.0, max(0.75, brightness * 1.4))

        // Keep saturation unchanged for more vivid colors (changed from 0.9 to 1.0)
        let adjustedSaturation = min(1.0, saturation * 1.0)

        return NSColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: alpha)
    }
}
