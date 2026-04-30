//
//  MenuBarIconRenderer.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit

/// Menu bar icon renderer
/// Handles all icon drawing logic, supporting both colored and monochrome modes
/// Extracted from MenuBarUI for separation of concerns
class MenuBarIconRenderer {
    
    // MARK: - Settings Reference
    
    /// User settings instance
    private let settings: UserSettings
    
    // MARK: - Initialization
    
    init(settings: UserSettings = .shared) {
        self.settings = settings
    }
    
    // MARK: - Public API
    
    /// Create menu bar icon for the given usage data.
    /// - Parameters:
    ///   - usageData: Usage data (nil → placeholder ring)
    ///   - button: Status bar button (used to get appearance mode)
    /// - Returns: The generated icon image
    func createIcon(usageData: UsageData?, button: NSStatusBarButton?) -> NSImage {
        // Show default icon when no data is available
        guard let data = usageData else {
            let size = NSSize(width: 22, height: 22)
            return settings.iconStyleMode == .monochrome ?
                createCircleTemplateImage(percentage: 0, size: size, button: button, removeBackground: true) :
                createCircleImage(percentage: 0, size: size, button: button, removeBackground: true)
        }

        let activeTypes = settings.getActiveDisplayTypes(usageData: data)

        // Determine if the colored theme can be used
        let canUseColor = settings.canUseColoredTheme(usageData: data)
        let forceMonochrome = !canUseColor && settings.iconStyleMode != .monochrome
        let isMonochrome = settings.iconStyleMode == .monochrome || forceMonochrome

        switch settings.iconDisplayMode {
        case .percentageOnly:
            return createCombinedPercentageIcon(data: data, types: activeTypes, isMonochrome: isMonochrome, button: button)

        case .iconOnly:
            let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
            if let appIcon = NSImage(named: iconName), let iconCopy = appIcon.copy() as? NSImage {
                iconCopy.size = NSSize(width: 18, height: 18)
                iconCopy.isTemplate = isMonochrome
                return iconCopy
            }
            return createSimpleCircleIcon()

        case .both:
            return createCombinedIconWithAppIcon(data: data, types: activeTypes, isMonochrome: isMonochrome, button: button)

        case .unified:
            return createUnifiedIcon(data: data, isMonochrome: isMonochrome, button: button)
        }
    }

    /// Create a combined percentage-only icon
    private func createCombinedPercentageIcon(
        data: UsageData,
        types: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        guard !types.isEmpty else {
            return createSimpleCircleIcon()
        }

        // Create icon for each type
        let icons = types.compactMap { type in
            createIconForType(type, data: data, isMonochrome: isMonochrome, button: button)
        }

        // Combine icons
        if icons.isEmpty {
            return createSimpleCircleIcon()
        } else if icons.count == 1 {
            return icons[0]
        } else {
            let combined = combineIcons(icons, spacing: 3.0, height: 18)
            combined.isTemplate = isMonochrome
            return combined
        }
    }

    /// Create a combined icon with app icon + percentage
    private func createCombinedIconWithAppIcon(
        data: UsageData,
        types: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        // Get the app icon (monochrome mode uses reversed icon)
        let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
        guard let appIcon = NSImage(named: iconName), let appIconCopy = appIcon.copy() as? NSImage else {
            return createCombinedPercentageIcon(data: data, types: types, isMonochrome: isMonochrome, button: button)
        }

        appIconCopy.size = NSSize(width: 18, height: 18)
        appIconCopy.isTemplate = isMonochrome

        // Create percentage icons
        let percentageIcons = types.compactMap { type in
            createIconForType(type, data: data, isMonochrome: isMonochrome, button: button)
        }

        // Combine app icon + percentage icons
        var allIcons = [appIconCopy]
        allIcons.append(contentsOf: percentageIcons)

        let combined = combineIcons(allIcons, spacing: 3.0, height: 18)
        combined.isTemplate = isMonochrome
        return combined
    }
    
    // MARK: - Vertical Text Column Mode

    /// Create unified concentric rings icon, optionally with percentage numbers
    private func createUnifiedIcon(
        data: UsageData,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        let fiveHourPct = data.fiveHour?.percentage
        let sevenDayPct = data.sevenDay?.percentage

        // If neither limit is available, show a placeholder
        guard fiveHourPct != nil || sevenDayPct != nil else {
            return createSimpleCircleIcon()
        }

        let hasBoth = fiveHourPct != nil && sevenDayPct != nil
        let iconSize: CGFloat = 22.0
        let size = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: iconSize / 2, y: iconSize / 2)
        let lineWidth: CGFloat = 2.0

        // Ring radii: outer = 7d (dashed), inner = 5h (solid)
        let outerRadius: CGFloat = iconSize / 2 - 2
        let innerRadius: CGFloat = outerRadius - lineWidth - 1.5

        // Helper: draw a progress ring
        func drawRing(percentage: Double, radius: CGFloat, color: NSColor, dashed: Bool) {
            // Background track
            let bgColor = isMonochrome ? NSColor.labelColor.withAlphaComponent(0.25) : NSColor.gray.withAlphaComponent(0.5)
            bgColor.setStroke()
            let bgPath = NSBezierPath()
            bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
            bgPath.lineWidth = 1.5
            if dashed {
                let dashPattern: [CGFloat] = [3, 1]
                bgPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            }
            bgPath.stroke()

            // Progress arc
            guard percentage > 0 else { return }
            color.setStroke()
            let progressPath = NSBezierPath()

            let baseAngle = CGFloat(percentage) / 100.0 * 360
            let circumference = 2 * CGFloat.pi * radius
            let capAngle = (lineWidth / circumference) * 360

            let progressAngle: CGFloat
            let startAngle: CGFloat

            if percentage >= 100 {
                progressAngle = baseAngle
                startAngle = 90
            } else {
                progressAngle = baseAngle - capAngle * min(1.0, CGFloat(percentage / 50.0))
                startAngle = 90 - capAngle / 2 + 0.5
            }

            let endAngle = startAngle - progressAngle
            progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            progressPath.lineWidth = lineWidth
            progressPath.lineCapStyle = percentage >= 100 ? .butt : .round
            progressPath.stroke()
        }

        // Draw rings
        if hasBoth, let fhPct = fiveHourPct, let sdPct = sevenDayPct {
            let outerColor: NSColor = isMonochrome ? NSColor.labelColor : UsageColorScheme.sevenDayColorAdaptive(sdPct, for: button)
            let innerColor: NSColor = isMonochrome ? NSColor.labelColor : UsageColorScheme.fiveHourColorAdaptive(fhPct, for: button)

            drawRing(percentage: sdPct, radius: outerRadius, color: outerColor, dashed: true)
            drawRing(percentage: fhPct, radius: innerRadius, color: innerColor, dashed: false)
        } else {
            // Single ring centered
            let pct = fiveHourPct ?? sevenDayPct ?? 0
            let isFiveHour = fiveHourPct != nil
            let color: NSColor
            if isMonochrome {
                color = NSColor.labelColor
            } else if isFiveHour {
                color = UsageColorScheme.fiveHourColorAdaptive(pct, for: button)
            } else {
                color = UsageColorScheme.sevenDayColorAdaptive(pct, for: button)
            }
            drawRing(percentage: pct, radius: outerRadius, color: color, dashed: !isFiveHour)
        }

        // Draw percentage text in center (only when showIconNumbers is enabled)
        if settings.showIconNumbers {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            func pctText(_ pct: Double) -> String {
                return "\(Int(min(pct, 999)))"
            }

            if hasBoth, let fhPct = fiveHourPct, let sdPct = sevenDayPct {
                // Two-line text: 5h on top, 7d on bottom
                let fontSize: CGFloat = 5.5
                let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)

                let topText = pctText(fhPct)
                let botText = pctText(sdPct)

                let topColor: NSColor = isMonochrome ? NSColor.black : UsageColorScheme.fiveHourColorAdaptive(fhPct, for: button)
                let botColor: NSColor = isMonochrome ? NSColor.black : UsageColorScheme.sevenDayColorAdaptive(sdPct, for: button)

                let topAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: topColor, .paragraphStyle: paragraphStyle]
                let botAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: botColor, .paragraphStyle: paragraphStyle]

                let topSize = (topText as NSString).size(withAttributes: topAttrs)
                let botSize = (botText as NSString).size(withAttributes: botAttrs)

                let totalTextHeight = topSize.height + botSize.height + 0.5
                let textTop = center.y + totalTextHeight / 2

                let topRect = NSRect(x: 0, y: textTop - topSize.height, width: iconSize, height: topSize.height)
                let botRect = NSRect(x: 0, y: textTop - topSize.height - 0.5 - botSize.height, width: iconSize, height: botSize.height)

                (topText as NSString).draw(in: topRect, withAttributes: topAttrs)
                (botText as NSString).draw(in: botRect, withAttributes: botAttrs)
            } else {
                // Single centered text
                let pct = fiveHourPct ?? sevenDayPct ?? 0
                let isFiveHour = fiveHourPct != nil
                let fontSize: CGFloat = pct >= 100 ? 6.0 : 7.5
                let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
                let text = pctText(pct)

                let color: NSColor
                if isMonochrome {
                    color = NSColor.black
                } else if isFiveHour {
                    color = UsageColorScheme.fiveHourColorAdaptive(pct, for: button)
                } else {
                    color = UsageColorScheme.sevenDayColorAdaptive(pct, for: button)
                }

                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]
                let textSize = (text as NSString).size(withAttributes: attrs)
                text.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attrs)
            }
        }

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    // MARK: - Icon Drawing - Colored Mode

    private func createCircleImage(percentage: Double, size: NSSize, useSevenDayColor: Bool = false, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        if !removeBackground {
            let backgroundCircle = NSBezierPath()
            backgroundCircle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
            NSColor.white.withAlphaComponent(0.5).setFill()
            backgroundCircle.fill()
        }

        NSColor.gray.withAlphaComponent(0.5).setStroke()
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        backgroundPath.lineWidth = 1.5

        // 7-day limit uses dashed line to distinguish from 5-hour limit
        if useSevenDayColor {
            let dashPattern: [CGFloat] = [3, 1]
            backgroundPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        backgroundPath.stroke()

        let color = useSevenDayColor ? UsageColorScheme.sevenDayColorAdaptive(percentage, for: button) : UsageColorScheme.fiveHourColorAdaptive(percentage, for: button)
        color.setStroke()

        let progressPath = NSBezierPath()
        let lineWidth: CGFloat = 2.5

        // Calculate progress angle
        let baseAngle = CGFloat(percentage) / 100.0 * 360
        let circumference = 2 * CGFloat.pi * radius  // Circumference
        let capAngle = (lineWidth / circumference) * 360  // Angle corresponding to round cap extension

        let progressAngle: CGFloat
        let startAngle: CGFloat

        if percentage >= 100 {
            // 100%: Use full angle with fixed start point, since .butt cap has no extension
            progressAngle = baseAngle
            startAngle = 90
        } else {
            // 5-hour/7-day limit: Use progressive subtraction, keeping start point fixed for smooth growth
            // Subtracted angle increases linearly with percentage, completing full subtraction at 50%, showing exact values from 50%-100%
            progressAngle = baseAngle - capAngle * min(1.0, CGFloat(percentage / 50.0))
            startAngle = 90 - capAngle / 2 + 0.5
        }

        let endAngle = startAngle - progressAngle

        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        // Use butt cap at 100% for a perfectly closed ring, round cap for other progress values
        progressPath.lineCapStyle = percentage >= 100 ? .butt : .round
        progressPath.stroke()

        if settings.showIconNumbers {
            let fontSize: CGFloat = percentage >= 100 ? size.width * 0.275 : size.width * 0.4
            let font = NSFont.systemFont(ofSize: fontSize, weight: percentage >= 100 ? .bold : .semibold)
            let text = "\(Int(percentage))"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let textColor = UsageColorScheme.isDarkMode(for: button) ? NSColor.white : NSColor.black

            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
            let textSize = text.size(withAttributes: attrs)
            let textOrigin = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
            text.draw(at: textOrigin, withAttributes: attrs)
        }

        image.unlockFocus()
        return image
    }

    // MARK: - Icon Drawing - Template Mode (Monochrome)

    private func createCircleTemplateImage(percentage: Double, size: NSSize, useSevenDayStyle: Bool = false, button: NSStatusBarButton? = nil, removeBackground: Bool = false) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        backgroundPath.lineWidth = 1.5

        // 7-day limit uses dashed line to distinguish from 5-hour limit
        if useSevenDayStyle {
            let dashPattern: [CGFloat] = [3, 1]
            backgroundPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        backgroundPath.stroke()

        NSColor.labelColor.setStroke()
        let progressPath = NSBezierPath()
        let lineWidth: CGFloat = 2.5

        // Calculate progress angle
        let baseAngle = CGFloat(percentage) / 100.0 * 360
        let circumference = 2 * CGFloat.pi * radius  // Circumference
        let capAngle = (lineWidth / circumference) * 360  // Angle corresponding to round cap extension

        let progressAngle: CGFloat
        let startAngle: CGFloat

        if percentage >= 100 {
            // 100%: Use full angle with fixed start point, since .butt cap has no extension
            progressAngle = baseAngle
            startAngle = 90
        } else {
            // Monochrome mode: Use progressive subtraction, keeping start point fixed for smooth growth
            // Subtracted angle increases linearly with percentage, completing full subtraction at 50%, showing exact values from 50%-100%
            progressAngle = baseAngle - capAngle * min(1.0, CGFloat(percentage / 50.0))
            startAngle = 90 - capAngle / 2 + 0.5
        }

        let endAngle = startAngle - progressAngle

        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        // Use butt cap at 100% for a perfectly closed ring, round cap for other progress values
        progressPath.lineCapStyle = percentage >= 100 ? .butt : .round
        progressPath.stroke()

        if settings.showIconNumbers {
            let fontSize: CGFloat = percentage >= 100 ? size.width * 0.275 : size.width * 0.4
            let font = NSFont.systemFont(ofSize: fontSize, weight: percentage >= 100 ? .bold : .semibold)
            let text = "\(Int(percentage))"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraphStyle]
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attrs)
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Utility Icons

    /// Create a simple circle icon (fallback)
    private func createSimpleCircleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 3, y: 3, width: 12, height: 12)
        let path = NSBezierPath(ovalIn: rect)

        NSColor.labelColor.setStroke()
        path.lineWidth = 2.0
        path.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Icon Combination Methods (v2.0)

    /// Combine multiple icons into a single image
    /// - Parameters:
    ///   - icons: Array of icons to combine
    ///   - spacing: Spacing between icons
    ///   - height: Uniform height (default 18)
    /// - Returns: Combined icon
    private func combineIcons(_ icons: [NSImage], spacing: CGFloat = 3.0, height: CGFloat = 18) -> NSImage {
        guard !icons.isEmpty else {
            return createSimpleCircleIcon()
        }

        // Calculate total width
        let totalWidth = icons.reduce(0) { $0 + $1.size.width } + CGFloat(icons.count - 1) * spacing
        let size = NSSize(width: totalWidth, height: height)

        let image = NSImage(size: size)
        image.lockFocus()

        var currentX: CGFloat = 0
        for icon in icons {
            let y = (height - icon.size.height) / 2  // Vertical centering
            icon.draw(at: NSPoint(x: currentX, y: y),
                     from: NSRect(origin: .zero, size: icon.size),
                     operation: .sourceOver,
                     fraction: 1.0)
            currentX += icon.size.width + spacing
        }

        image.unlockFocus()
        return image
    }

    /// Create a single icon based on limit type and data
    /// - Parameters:
    ///   - type: Limit type
    ///   - data: Usage data
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button
    /// - Returns: Icon image
    func createIconForType(
        _ type: LimitType,
        data: UsageData,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage? {
        // Decide whether to remove background based on theme mode
        // colorTranslucent: Remove background (translucent)
        // colorWithBackground: Keep background (semi-transparent white)
        let removeBackground = settings.iconStyleMode == .colorTranslucent

        // In custom mode, show placeholder icon (0%) even when data is nil
        // In smart mode, return nil when data is nil
        let showPlaceholder = settings.displayMode == .custom

        switch type {
        case .fiveHour:
            let percentage = data.fiveHour?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: true)
            } else {
                return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: removeBackground)
            }

        case .sevenDay:
            let percentage = data.sevenDay?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayStyle: true, button: button, removeBackground: true)
            } else {
                return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayColor: true, button: button, removeBackground: removeBackground)
            }

        case .opusWeekly:
            let percentage = data.opus?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createVerticalRectangleIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        case .sonnetWeekly:
            let percentage = data.sonnet?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createHorizontalRectangleIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        case .extraUsage:
            let percentage: Double?
            if let extraUsage = data.extraUsage, extraUsage.enabled {
                percentage = extraUsage.percentage
            } else if showPlaceholder {
                percentage = 0
            } else {
                percentage = nil
            }
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createHexagonIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)
        }
    }

}
