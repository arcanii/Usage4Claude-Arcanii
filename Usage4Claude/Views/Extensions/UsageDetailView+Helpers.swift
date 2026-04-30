//
//  UsageDetailView+Helpers.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Helper Methods Extension

extension UsageDetailView {

    // MARK: - Animation Methods

    /// Start rotation animation
    func startRotationAnimation() {
        // Clear old timer
        stopRotationAnimation()

        // Reset angle
        rotationAngle = 0

        // Create new timer, updating every 0.016 seconds (~60fps)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                rotationAngle += 6  // Rotate 6 degrees per frame, completing one full rotation per second
                if rotationAngle >= 360 {
                    rotationAngle -= 360
                }
            }
        }
    }

    /// Stop rotation animation
    func stopRotationAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        withAnimation(.default) {
            rotationAngle = 0
        }
    }

    /// Loading animation view
    /// Returns different loading effects based on animationType
    @ViewBuilder
    func loadingAnimation() -> some View {
        switch animationType {
        case .rainbow:
            rainbowLoadingAnimation()
        case .dashed:
            dashedLoadingAnimation()
        case .pulse:
            pulseLoadingAnimation()
        }
    }

    /// Effect 1: Rainbow gradient rotation (recommended)
    func rainbowLoadingAnimation() -> some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [.blue, .purple, .pink, .orange, .blue]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 10, lineCap: .round)
            )
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(rotationAngle))
    }

    /// Effect 2: Dashed rotation
    func dashedLoadingAnimation() -> some View {
        Circle()
            .trim(from: 0, to: 1)
            .stroke(
                Color.blue,
                style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [10, 8])
            )
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(rotationAngle))
    }

    /// Effect 3: Pulse effect
    func pulseLoadingAnimation() -> some View {
        ZStack {
            // Inner ring - fast pulse
            Circle()
                .trim(from: 0, to: 0.6)
                .stroke(
                    Color.blue.opacity(0.8),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(rotationAngle))

            // Outer ring - slow pulse
            Circle()
                .trim(from: 0, to: 0.4)
                .stroke(
                    Color.blue.opacity(0.4),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-rotationAngle * 0.7))
        }
    }

    /// Outer ring rainbow loading animation (counter-clockwise rotation)
    func outerRainbowLoadingAnimation() -> some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [.blue, .purple, .pink, .orange, .blue]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 114, height: 114)
            .rotationEffect(.degrees(-rotationAngle))  // Counter-clockwise rotation
    }

    /// Outer ring dashed loading animation (counter-clockwise rotation)
    func outerDashedLoadingAnimation() -> some View {
        Circle()
            .trim(from: 0, to: 1)
            .stroke(
                Color.purple,  // Use purple theme consistent with 7-day limit
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6])
            )
            .frame(width: 114, height: 114)
            .rotationEffect(.degrees(-rotationAngle))  // Counter-clockwise rotation
    }

    /// Outer ring pulse loading animation (counter-clockwise rotation)
    func outerPulseLoadingAnimation() -> some View {
        Circle()
            .trim(from: 0, to: 0.4)
            .stroke(
                Color.purple.opacity(0.6),  // Use purple theme consistent with 7-day limit
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 114, height: 114)
            .rotationEffect(.degrees(-rotationAngle * 0.7))  // Slow counter-clockwise rotation
    }

    /// Outer ring loading animation view (returns corresponding effect based on animationType)
    @ViewBuilder
    func outerLoadingAnimation() -> some View {
        switch animationType {
        case .rainbow:
            outerRainbowLoadingAnimation()
        case .dashed:
            outerDashedLoadingAnimation()
        case .pulse:
            outerPulseLoadingAnimation()
        }
    }

    // MARK: - Primary Limit Selection

    /// Determine primary limit data based on user-selected display types
    /// - Parameters:
    ///   - data: Usage data
    ///   - activeTypes: Currently active display types
    /// - Returns: Primary limit data
    func getPrimaryLimitData(data: UsageData, activeTypes: [LimitType]) -> UsageData.LimitData? {
        // In custom mode, show placeholder data (0%) even when data is nil
        let showPlaceholder = UserSettings.shared.displayMode == .custom
        let placeholderData = UsageData.LimitData(percentage: 0, resetsAt: nil)

        // Find the first circular type from active types
        if activeTypes.contains(.fiveHour) {
            if let fiveHour = data.fiveHour {
                return fiveHour
            } else if showPlaceholder {
                return placeholderData
            }
        } else if activeTypes.contains(.sevenDay) {
            if let sevenDay = data.sevenDay {
                return sevenDay
            } else if showPlaceholder {
                return placeholderData
            }
        }
        // If no circular type found, return nil
        return nil
    }

    /// Determine primary limit color based on user-selected display types
    /// - Parameters:
    ///   - data: Usage data
    ///   - activeTypes: Currently active display types
    /// - Returns: Primary limit color
    func colorForPrimaryByActiveTypes(data: UsageData, activeTypes: [LimitType]) -> Color {
        // Find the first circular type from active types and return its color
        if activeTypes.contains(.fiveHour) {
            if let fiveHour = data.fiveHour {
                return colorForPercentage(fiveHour.percentage)
            } else {
                // Return gray when data is nil
                return .gray
            }
        } else if activeTypes.contains(.sevenDay) {
            if let sevenDay = data.sevenDay {
                return colorForSevenDay(sevenDay.percentage)
            } else {
                return .gray
            }
        }
        return .gray
    }

    // MARK: - Color Methods

    /// Return color based on usage percentage
    /// - 0-70%: Green (safe)
    /// - 70-90%: Orange (warning)
    /// - 90-100%: Red (danger)
    /// Return color based on 5-hour limit usage percentage
    /// - Parameter percentage: Current usage percentage
    /// - Returns: Corresponding status color
    /// - Note: Uses unified color scheme (green -> orange -> red)
    func colorForPercentage(_ percentage: Double) -> Color {
        return UsageColorScheme.fiveHourColorSwiftUI(percentage)
    }

    /// Return color based on 7-day limit usage percentage
    /// - Parameter percentage: Current usage percentage
    /// - Returns: Corresponding status color
    /// - Note: Uses unified color scheme (cyan-blue -> blue-purple -> deep purple)
    func colorForSevenDay(_ percentage: Double) -> Color {
        return UsageColorScheme.sevenDayColorSwiftUI(percentage)
    }

    /// Get primary limit color (automatically selects green/orange/red or purple theme based on data type)
    func colorForPrimary(_ data: UsageData) -> Color {
        if let fiveHour = data.fiveHour {
            // Has 5-hour limit data, use green/orange/red
            return colorForPercentage(fiveHour.percentage)
        } else if let sevenDay = data.sevenDay {
            // Only 7-day limit data, use purple theme
            return colorForSevenDay(sevenDay.percentage)
        }
        return .gray
    }

}
