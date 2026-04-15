//
//  ShapeIconRenderer.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

/// Shape icon renderer
/// Responsible for drawing progress rings for non-circular icons (rectangle, diamond, hexagon)
class ShapeIconRenderer {

    // MARK: - Helper Methods

    /// Calculate opacity for monochrome theme (based on percentage)
    /// - Parameter percentage: Usage percentage (0-100)
    /// - Returns: Opacity (0.8-1.0)
    static func monochromeOpacity(for percentage: Double) -> CGFloat {
        if percentage <= 50 {
            return 0.8
        } else if percentage <= 75 {
            return 0.9
        } else {
            return 1.0
        }
    }

    // MARK: - Shape Drawing Methods

    /// Draw rounded square progress ring and percentage (for Opus)
    /// - Parameters:
    ///   - rect: Drawing area
    ///   - percentage: Usage percentage
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button (for obtaining color)
    ///   - removeBackground: Whether to remove background fill
    static func drawRoundedSquareWithPercentage(in rect: NSRect, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) {
        let cornerRadius: CGFloat = 3.0
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress line
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // 1. Draw background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            let backgroundFillPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.5).setFill()
            backgroundFillPath.fill()
        }

        // 2. Draw background border
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.5).setStroke()
        }
        backgroundPath.lineWidth = borderWidth
        backgroundPath.stroke()

        // 2. Draw progress border (clockwise, starting from 12 o'clock)
        if percentage > 0 {
            // Calculate actual perimeter of the rounded square
            // Perimeter = 4 straight segments + 4 corner arcs
            // Total straight length = 4 * (side length - 2*cornerRadius)
            // Total arc length = 4 * (pi*cornerRadius/2) = 2*pi*cornerRadius
            let straightLength = 4 * (rect.width - 2 * cornerRadius)
            let arcLength = 2 * CGFloat.pi * cornerRadius
            let perimeter = straightLength + arcLength

            // Calculate progress length
            // Uses progressive subtraction: subtracted length increases linearly with percentage, full subtraction at 50%
            // < 50%: smooth growth, subtraction gradually increases from 0 to progressWidth
            // >= 50%: fully precise, always subtracts full progressWidth
            // = 100%: no subtraction because .butt line cap is used (no extension)
            let baseProgressLength = perimeter * CGFloat(percentage / 100.0)
            let progressLength = percentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(percentage / 50.0)))

            // Manually build a clockwise path starting from 12 o'clock
            let progressPath = NSBezierPath()

            // Start from 12 o'clock position (middle of top edge)
            let startPoint = NSPoint(x: rect.midX, y: rect.maxY)
            progressPath.move(to: startPoint)

            // Draw clockwise: 12 -> 3 -> 6 -> 9 -> back to 12
            // Top-right corner (need to account for rounded corner)
            progressPath.line(to: NSPoint(x: rect.maxX - cornerRadius, y: rect.maxY))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 90,
                endAngle: 0,
                clockwise: true
            )

            // Right edge to bottom-right corner
            progressPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: 270,
                clockwise: true
            )

            // Bottom edge to bottom-left corner
            progressPath.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.minY))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 180,
                clockwise: true
            )

            // Left edge to top-left corner
            progressPath.line(to: NSPoint(x: rect.minX, y: rect.maxY - cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 90,
                clockwise: true
            )

            // Top edge back to start point
            progressPath.line(to: startPoint)

            // Draw using dash pattern
            // < 100%: use negative phase to pre-draw half a round cap at the start, distributing subtracted lineWidth evenly at both ends
            let phase: CGFloat = percentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressPath.setLineDash(pattern, count: 2, phase: phase)
            progressPath.lineWidth = progressWidth
            // At 100% use butt cap for perfect closure, other progress uses round cap
            progressPath.lineCapStyle = percentage >= 100 ? .butt : .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                UsageColorScheme.opusWeeklyColorAdaptive(percentage, for: button).setStroke()
            }
            progressPath.stroke()
        }

        // 3. Draw percentage text (only when showIconNumbers is enabled)
        if UserSettings.shared.showIconNumbers {
            let percentageText = "\(Int(percentage))"
            let percentageFontSize: CGFloat = percentage >= 100 ? 5.0 : 7.2
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: percentageFontSize, weight: percentage >= 100 ? .bold : .semibold),
                .foregroundColor: UsageColorScheme.isDarkMode ? NSColor.white : NSColor.black
            ]
            let textSize = percentageText.size(withAttributes: attributes)
            let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
            percentageText.draw(in: textRect, withAttributes: attributes)
        }
    }

    /// Draw diamond progress ring and percentage (for Sonnet - 45-degree rotated square)
    /// - Parameters:
    ///   - rect: Drawing area
    ///   - percentage: Usage percentage
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button (for obtaining color)
    ///   - removeBackground: Whether to remove background fill
    static func drawDiamondWithPercentage(in rect: NSRect, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) {
        // Identical parameter setup as Opus
        let cornerRadius: CGFloat = 3.0
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress line
        let cutSize: CGFloat = 3.5  // Top-right chamfer size (slightly smaller fine-tuning)
        let center = NSPoint(x: rect.midX, y: rect.midY)

        // Create rounded rectangle path with top-right chamfer (same as Opus, just with top-right corner cut)
        func createChamferedRectPath(_ rect: NSRect) -> NSBezierPath {
            let path = NSBezierPath()

            // Start from bottom-left corner (with rounded corner)
            path.move(to: NSPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 270,
                clockwise: false
            )

            // Bottom edge to bottom-right corner (with rounded corner)
            path.line(to: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 0,
                clockwise: false
            )

            // Right edge to chamfer position
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cutSize))

            // Chamfer line
            path.line(to: NSPoint(x: rect.maxX - cutSize, y: rect.maxY))

            // Top edge to top-left corner (with rounded corner)
            path.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 90,
                endAngle: 180,
                clockwise: false
            )

            // Back to start point
            path.close()

            return path
        }

        // 1. Draw background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            let backgroundFillPath = createChamferedRectPath(rect)
            NSColor.white.withAlphaComponent(0.5).setFill()
            backgroundFillPath.fill()
        }

        // 2. Draw background border (identical to Opus)
        let backgroundPath = createChamferedRectPath(rect)
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.5).setStroke()
        }
        backgroundPath.lineWidth = borderWidth
        backgroundPath.stroke()

        // 2. Draw progress border (clockwise, starting from 12 o'clock)
        if percentage > 0 {
            // Manually build a clockwise path starting from 12 o'clock (with top-right chamfer)
            let progressPath = NSBezierPath()

            // Start from 12 o'clock position (middle of top edge)
            let startPoint = NSPoint(x: rect.midX, y: rect.maxY)
            progressPath.move(to: startPoint)

            // Draw clockwise: 12 -> top-right chamfer -> 3 -> 6 -> 9 -> back to 12
            // Top edge to top-right chamfer position
            progressPath.line(to: NSPoint(x: rect.maxX - cutSize, y: rect.maxY))

            // Top-right chamfer line
            progressPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY - cutSize))

            // Right edge to bottom-right corner
            progressPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: 270,
                clockwise: true
            )

            // Bottom edge to bottom-left corner
            progressPath.line(to: NSPoint(x: rect.minX + cornerRadius, y: rect.minY))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: 270,
                endAngle: 180,
                clockwise: true
            )

            // Left edge to top-left corner
            progressPath.line(to: NSPoint(x: rect.minX, y: rect.maxY - cornerRadius))
            progressPath.appendArc(
                withCenter: NSPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 180,
                endAngle: 90,
                clockwise: true
            )

            // Top edge back to start point
            progressPath.line(to: startPoint)

            // Calculate actual perimeter of the chamfered square
            // Based on Opus's rounded square perimeter, then adjust for the chamfer:
            // 1. Opus perimeter = 4 straight segments + 4 corner arcs
            let opusStraightLength = 4 * (rect.width - 2 * cornerRadius)
            let opusArcLength = 2 * CGFloat.pi * cornerRadius
            let opusPerimeter = opusStraightLength + opusArcLength

            // 2. Sonnet's top-right chamfer causes:
            //    - Removed one 90-degree corner arc: -cornerRadius * pi/2
            //    - Top edge from (width-2*corner) to (width-corner-cut): +cornerRadius-cutSize
            //    - Right edge from (width-2*corner) to (width-corner-cut): +cornerRadius-cutSize
            //    - Added chamfer line: +cutSize * sqrt(2)
            //    Total: 2*cornerRadius - 2*cutSize + cutSize*sqrt(2) - cornerRadius*pi/2
            let cornerArcReduction = -cornerRadius * .pi / 2
            let edgeAdjustment = 2.0 * cornerRadius
            let cutAdjustment = cutSize * (sqrt(2.0) - 2.0)
            let perimeter = opusPerimeter + cornerArcReduction + edgeAdjustment + cutAdjustment

            // Calculate progress length
            // Uses progressive subtraction: subtracted length increases linearly with percentage, full subtraction at 50%
            // < 50%: smooth growth, subtraction gradually increases from 0 to progressWidth
            // >= 50%: fully precise, always subtracts full progressWidth
            // = 100%: no subtraction because .butt line cap is used (no extension)
            let baseProgressLength = perimeter * CGFloat(percentage / 100.0)
            let progressLength = percentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(percentage / 50.0)))

            // Draw using dash pattern
            // < 100%: use negative phase to pre-draw half a round cap at the start, distributing subtracted lineWidth evenly at both ends
            let phase: CGFloat = percentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressPath.setLineDash(pattern, count: 2, phase: phase)
            progressPath.lineWidth = progressWidth
            // At 100% use butt cap for perfect closure, other progress uses round cap
            progressPath.lineCapStyle = percentage >= 100 ? .butt : .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                UsageColorScheme.sonnetWeeklyColorAdaptive(percentage, for: button).setStroke()
            }
            progressPath.stroke()
        }

        // 3. Draw percentage text (only when showIconNumbers is enabled)
        if UserSettings.shared.showIconNumbers {
            let percentageText = "\(Int(percentage))"
            let percentageFontSize: CGFloat = percentage >= 100 ? 5.0 : 7.2
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: percentageFontSize, weight: percentage >= 100 ? .bold : .semibold),
                .foregroundColor: UsageColorScheme.isDarkMode ? NSColor.white : NSColor.black
            ]
            let textSize = percentageText.size(withAttributes: attributes)
            let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
            percentageText.draw(in: textRect, withAttributes: attributes)
        }
    }

    /// Draw flat-top hexagon progress ring and percentage (for Extra Usage)
    /// - Parameters:
    ///   - center: Center point
    ///   - size: Hexagon size
    ///   - percentage: Usage percentage
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button (for obtaining color)
    ///   - removeBackground: Whether to remove background fill
    static func drawHexagonWithPercentage(center: NSPoint, size: CGFloat, percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) {
        let radius = size / 2
        let borderWidth: CGFloat = 1.5
        let progressWidth: CGFloat = 2.5  // Thicker progress line

        // Create flat-top hexagon path (flat top - top and bottom edges are flat)
        let hexagonPath = NSBezierPath()
        for i in 0..<6 {
            let angle = CGFloat(i) * CGFloat.pi / 3.0  // Maintain flat-top orientation
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 {
                hexagonPath.move(to: NSPoint(x: x, y: y))
            } else {
                hexagonPath.line(to: NSPoint(x: x, y: y))
            }
        }
        hexagonPath.close()

        // 1. Draw background fill (colored background mode)
        if !removeBackground && !isMonochrome {
            NSColor.white.withAlphaComponent(0.5).setFill()
            hexagonPath.fill()
        }

        // 2. Draw background border
        if isMonochrome {
            NSColor.controlTextColor.withAlphaComponent(0.3).setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.5).setStroke()
        }
        hexagonPath.lineWidth = borderWidth
        hexagonPath.lineJoinStyle = .round
        hexagonPath.stroke()

        // 2. Draw progress border
        if percentage > 0 {
            // Calculate hexagon perimeter
            let sideLength = radius  // Regular hexagon side length equals the radius
            let perimeter = sideLength * 6

            // Calculate progress length
            // Uses progressive subtraction: subtracted length increases linearly with percentage, full subtraction at 50%
            // < 50%: smooth growth, subtraction gradually increases from 0 to progressWidth
            // >= 50%: fully precise, always subtracts full progressWidth
            // = 100%: no subtraction because .butt line cap is used (no extension)
            let baseProgressLength = perimeter * CGFloat(percentage / 100.0)
            let progressLength = percentage >= 100 ? baseProgressLength : (baseProgressLength - progressWidth * min(1.0, CGFloat(percentage / 50.0)))

            // Manually build a clockwise path starting from the 12 o'clock top position
            // First calculate 6 vertex positions (maintain flat-top orientation)
            var vertices: [NSPoint] = []
            for i in 0..<6 {
                let angle = CGFloat(i) * CGFloat.pi / 3.0
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                vertices.append(NSPoint(x: x, y: y))
            }
            // vertices[0] = 3 o'clock (right)
            // vertices[1] = 1 o'clock (top-right)
            // vertices[2] = 11 o'clock (top-left)
            // vertices[3] = 9 o'clock (left)
            // vertices[4] = 7 o'clock (bottom-left)
            // vertices[5] = 5 o'clock (bottom-right)

            // Start from 12 o'clock position (midpoint of top edge, between vertices[1] and vertices[2])
            let topMidpoint = NSPoint(
                x: (vertices[1].x + vertices[2].x) / 2,
                y: (vertices[1].y + vertices[2].y) / 2
            )

            let progressHexagon = NSBezierPath()
            progressHexagon.move(to: topMidpoint)

            // Clockwise direction: 12 -> 1 -> 3 -> 5 -> 7 -> 9 -> 11 -> back to 12
            progressHexagon.line(to: vertices[1])  // To 1 o'clock vertex
            progressHexagon.line(to: vertices[0])  // To 3 o'clock vertex
            progressHexagon.line(to: vertices[5])  // To 5 o'clock vertex
            progressHexagon.line(to: vertices[4])  // To 7 o'clock vertex
            progressHexagon.line(to: vertices[3])  // To 9 o'clock vertex
            progressHexagon.line(to: vertices[2])  // To 11 o'clock vertex
            progressHexagon.line(to: topMidpoint)  // Back to 12 o'clock

            // Draw using dash pattern
            // < 100%: use negative phase to pre-draw half a round cap at the start, distributing subtracted lineWidth evenly at both ends
            let phase: CGFloat = percentage >= 100 ? 0 : -progressWidth / 2
            let pattern: [CGFloat] = [progressLength, perimeter - progressLength]
            progressHexagon.setLineDash(pattern, count: 2, phase: phase)
            progressHexagon.lineWidth = progressWidth
            // At 100% use butt cap for perfect closure, other progress uses round cap
            progressHexagon.lineCapStyle = percentage >= 100 ? .butt : .round
            progressHexagon.lineJoinStyle = .round

            if isMonochrome {
                let opacity = monochromeOpacity(for: percentage)
                NSColor.controlTextColor.withAlphaComponent(opacity).setStroke()
            } else {
                UsageColorScheme.extraUsageColorAdaptive(percentage, for: button).setStroke()
            }
            progressHexagon.stroke()
        }

        // 3. Draw percentage text (only when showIconNumbers is enabled)
        if UserSettings.shared.showIconNumbers {
            let percentageText = "\(Int(percentage))"
            let percentageFontSize: CGFloat = percentage >= 100 ? 5.0 : 7.2
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: percentageFontSize, weight: percentage >= 100 ? .bold : .semibold),
                .foregroundColor: UsageColorScheme.isDarkMode ? NSColor.white : NSColor.black
            ]
            let textSize = percentageText.size(withAttributes: attributes)
            let textRect = NSRect(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2, width: textSize.width, height: textSize.height)
            percentageText.draw(in: textRect, withAttributes: attributes)
        }
    }

    // MARK: - Icon Creation Methods

    /// Create rounded square icon (Opus)
    /// - Parameters:
    ///   - percentage: Usage percentage
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button
    ///   - removeBackground: Whether to remove background fill
    /// - Returns: Icon image (18x18)
    static func createVerticalRectangleIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 2, dy: 2)
        drawRoundedSquareWithPercentage(in: rect, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    /// Create diamond icon (Sonnet - 45-degree rotated square)
    /// - Parameters:
    ///   - percentage: Usage percentage
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button
    ///   - removeBackground: Whether to remove background fill
    /// - Returns: Icon image (18x18)
    static func createHorizontalRectangleIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: 2, dy: 2)
        drawDiamondWithPercentage(in: rect, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }

    /// Create flat-top hexagon icon (Extra Usage)
    /// - Parameters:
    ///   - percentage: Usage percentage
    ///   - isMonochrome: Whether in monochrome mode
    ///   - button: Status bar button
    ///   - removeBackground: Whether to remove background (default false)
    /// - Returns: Icon image (18x18)
    static func createHexagonIcon(percentage: Double, isMonochrome: Bool, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        drawHexagonWithPercentage(center: center, size: 16, percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }
}
