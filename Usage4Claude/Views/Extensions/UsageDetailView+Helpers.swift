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

    // MARK: - Error Classification

    /// Whether an error message describes an authentication problem (and so the
    /// popover should offer a "Go to Settings" button).
    ///
    /// `errorMessage` is always a `UsageError.localizedDescription`, so compare it
    /// against the localized strings themselves. The previous implementation
    /// substring-matched hardcoded words ("认证"/"配置"/"Authentication"/"configured"),
    /// which only ever matched English and Simplified Chinese — Japanese, Korean,
    /// and Traditional Chinese users never saw the button.
    func isAuthenticationError(_ message: String) -> Bool {
        message == L.Error.noCredentials
            || message == L.Error.sessionExpired
            || message == L.Error.unauthorized
    }

    // MARK: - Primary Limit Selection

    /// Which limit the large ring shows. The decision lives in `LimitDisplayLayout`,
    /// where it is unit tested; this supplies the popover's placeholder setting.
    func primaryRingType(data: UsageData, activeTypes: [LimitType]) -> LimitType? {
        LimitDisplayLayout.primaryRingType(
            data: data,
            activeTypes: activeTypes,
            showPlaceholder: UserSettings.shared.shouldShowCustomPlaceholderInPopover
        )
    }

    /// Whether to draw the thin outer 7-day ring and stack both percentages in the
    /// center. See `LimitDisplayLayout.showsSevenDayOuterRing`.
    func showsSevenDayOuterRing(data: UsageData, activeTypes: [LimitType]) -> Bool {
        LimitDisplayLayout.showsSevenDayOuterRing(
            data: data,
            activeTypes: activeTypes,
            showPlaceholder: UserSettings.shared.shouldShowCustomPlaceholderInPopover
        )
    }

    /// Determine primary limit data based on user-selected display types
    /// - Parameters:
    ///   - data: Usage data
    ///   - activeTypes: Currently active display types
    /// - Returns: Primary limit data, a 0% placeholder in custom mode when the chosen
    ///   limit has no data, or nil when no ring should be drawn
    func getPrimaryLimitData(data: UsageData, activeTypes: [LimitType]) -> UsageData.LimitData? {
        let placeholderData = UsageData.LimitData(percentage: 0, resetsAt: nil)

        switch primaryRingType(data: data, activeTypes: activeTypes) {
        case .fiveHour:
            return data.fiveHour ?? placeholderData
        case .sevenDay:
            return data.sevenDay ?? placeholderData
        default:
            return nil
        }
    }

    /// Determine primary limit color based on user-selected display types
    /// - Parameters:
    ///   - data: Usage data
    ///   - activeTypes: Currently active display types
    /// - Returns: Primary limit color, gray for a placeholder
    func colorForPrimaryByActiveTypes(data: UsageData, activeTypes: [LimitType]) -> Color {
        switch primaryRingType(data: data, activeTypes: activeTypes) {
        case .fiveHour:
            return data.fiveHour.map { colorForPercentage($0.percentage) } ?? .gray
        case .sevenDay:
            return data.sevenDay.map { colorForSevenDay($0.percentage) } ?? .gray
        default:
            return .gray
        }
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
