//
//  UsageDetailView.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Usage detail view
/// Displays Claude's current usage status, including percentage progress bar, countdown, and reset time
struct UsageDetailView: View {
    @Binding var usageData: UsageData?
    @Binding var errorMessage: String?
    @ObservedObject var refreshState: RefreshState
    /// Menu action callback
    var onMenuAction: ((MenuAction) -> Void)? = nil
    @StateObject private var localization = LocalizationManager.shared
    /// Live-updating settings — observed so the ring illumination slider
    /// re-renders the popover while the user drags it from General Settings.
    @ObservedObject private var settings = UserSettings.shared
    
    /// Loading animation effect type
    enum LoadingAnimationType: Int, CaseIterable {
        case rainbow = 0   // Rainbow gradient rotation
        case dashed = 1    // Dashed rotation
        case pulse = 2     // Pulse effect

        var name: String {
            switch self {
            case .rainbow: return L.LoadingAnimation.rainbow
            case .dashed: return L.LoadingAnimation.dashed
            case .pulse: return L.LoadingAnimation.pulse
            }
        }
    }

    // Currently used loading animation type (can be switched by long-pressing the ring)
    @State var animationType: LoadingAnimationType = .rainbow
    
    /// Menu action type
    enum MenuAction {
        case generalSettings
        case authSettings
        case checkForUpdates
        case about
        case webUsage
        case quit
        case refresh
    }
    
    // Animation state (passed from outside to avoid resetting on each view rebuild)
    @State var rotationAngle: Double = 0
    @State var animationTimer: Timer?
    // Show animation type switch hint
    @State private var showAnimationTypeHint = false
    // Display mode toggle (false: reset time, true: remaining time)
    @AppStorage("showRemainingMode") private var savedRemainingMode = false
    @State private var showRemainingMode = false
    
    // MARK: - Body

    /// Get current active display types
    private var activeDisplayTypes: [LimitType] {
        guard let data = usageData else { return [] }
        return UserSettings.shared.getActiveDisplayTypes(usageData: data)
    }

    /// Calculate dynamic height based on the number of active types
    private var dynamicHeight: CGFloat {
        let activeCount = activeDisplayTypes.count

        // Base height: title + main ring + bottom margin.
        // Row height: HStack content (22) + vstack spacing (3) + sparkline (14) +
        // vertical padding (8) ≈ 47pt. Padded to 48 for breathing room.
        let baseHeight: CGFloat = 190
        let rowHeight: CGFloat = 48
        let spacing: CGFloat = 5

        // Single limit always shows 2 rows; dual and 3+ limits show corresponding row count
        let rowCount = activeCount == 1 ? 2 : activeCount
        let textHeight = CGFloat(rowCount) * rowHeight + CGFloat(max(0, rowCount - 1)) * spacing

        return baseHeight + textHeight
    }

    var body: some View {
        VStack(spacing: activeDisplayTypes.count >= 2 ? 10 : 16) {  // Reduce spacing for multiple limits
            // Title
            HStack {
                // App icon (not using template mode)
                if let icon = ImageHelper.createAppIcon(size: 20) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "chart.pie.fill")
                        .foregroundColor(.blue)
                }
                
                Text(L.Usage.title)
                    .font(.headline)
                
                Spacer()
                
                // Refresh button (left side)
                Button(action: {
                    onMenuAction?(.refresh)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .opacity(refreshState.canRefresh ? 1.0 : 0.3)
                        .rotationEffect(.degrees(refreshState.isRefreshing ? rotationAngle : 0))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!refreshState.canRefresh || refreshState.isRefreshing)
                .focusable(false)  // Disable focus state
                .onAppear {
                    // If already refreshing when opened, start the animation
                    if refreshState.isRefreshing {
                        startRotationAnimation()
                    }
                }
                .onChange(of: refreshState.isRefreshing) { newValue in
                    if newValue {
                        startRotationAnimation()
                    } else {
                        stopRotationAnimation()
                    }
                }
                
                // Ellipsis menu button (right side) + badge
                ZStack(alignment: .topTrailing) {
                    Menu {
                        // Account switch submenu (only shown when multiple accounts exist)
                        if UserSettings.shared.accounts.count > 1 {
                            Menu {
                                ForEach(UserSettings.shared.accounts) { account in
                                    Button(action: {
                                        UserSettings.shared.switchToAccount(account)
                                    }) {
                                        HStack {
                                            Text(account.displayName)
                                            if account.id == UserSettings.shared.currentAccountId {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                let name = UserSettings.shared.currentAccountName ?? L.Menu.account
                                Label("\(L.Menu.accountPrefix) \(name)", systemImage: "person.2")
                            }
                            Divider()
                        }

                        Button(action: { onMenuAction?(.generalSettings) }) {
                            Label(L.Menu.generalSettings, systemImage: "gearshape")
                        }
                        Button(action: { onMenuAction?(.authSettings) }) {
                            Label(L.Menu.authSettings, systemImage: "key")
                        }

                        // Check for updates (Sparkle owns the prompt — single style here)
                        Button(action: { onMenuAction?(.checkForUpdates) }) {
                            Label(L.Menu.checkUpdates, systemImage: "arrow.triangle.2.circlepath")
                        }

                        Button(action: { onMenuAction?(.about) }) {
                            Label(L.Menu.about, systemImage: "info.circle")
                        }
                        Divider()
                        Button(action: { onMenuAction?(.webUsage) }) {
                            Label(L.Menu.webUsage, systemImage: "safari")
                        }
                        Divider()
                        Button(action: { onMenuAction?(.quit) }) {
                            Label(L.Menu.quit, systemImage: "power")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(90))
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            if let error = errorMessage {
                // Error message
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    // Action button group
                    HStack(spacing: 12) {
                        // If it's an authentication error, show settings button
                        if error.contains("认证") || error.contains("配置") || error.contains("Authentication") || error.contains("configured") {
                            Button(action: {
                                onMenuAction?(.authSettings)
                            }) {
                                Label(L.Usage.goToSettings, systemImage: "key.fill")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }

                        // Diagnostic connection button (shown for all errors)
                        Button(action: {
                            onMenuAction?(.authSettings)
                            // Note: this actually opens the auth settings tab; diagnostics are at the bottom of that page
                        }) {
                            Label(L.Usage.runDiagnostic, systemImage: "stethoscope")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            } else if let data = usageData {
                // Usage data
                VStack(spacing: 15) {  // Top spacing for two text rows in dual mode
                    // Circular progress bar
                    ZStack {
                        // Determine primary limit based on user-selected display types
                        let primaryLimitData = getPrimaryLimitData(data: data, activeTypes: activeDisplayTypes)

                        if let primary = primaryLimitData {
                            // 1. Main ring background (gray)
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                                .frame(width: 100, height: 100)

                            if refreshState.isRefreshing {
                                // Loading animation
                                loadingAnimation()
                            } else {
                                // 2. Main progress arc (based on user-selected limit type).
                                // Stacked shadows give the stroke a glow halo — small radius
                                // for a hot core, larger radius for ambient bloom.
                                let primaryColor = colorForPrimaryByActiveTypes(data: data, activeTypes: activeDisplayTypes)
                                // Glass-tube effect: stroke gradient gives the body
                                // (specular highlight at top, dimmer middle, ambient
                                // reflection at bottom). On macOS 26 we layer Apple's
                                // Liquid Glass material for a real refractive feel;
                                // older macOS falls back to the gradient + shadow only.
                                let primaryGlass = LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.85), location: 0.0),
                                        .init(color: primaryColor, location: 0.25),
                                        .init(color: primaryColor.opacity(0.6), location: 0.55),
                                        .init(color: primaryColor.opacity(0.95), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                // User-tunable illumination: scales shadow opacity/radius
                                // linearly; gates the Liquid Glass material above 0.5 since
                                // the material itself isn't continuously dimmable.
                                let illumination = settings.ringIlluminationLevel
                                Circle()
                                    .trim(from: 0, to: CGFloat(primary.percentage) / 100.0)
                                    .stroke(
                                        primaryGlass,
                                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                    )
                                    .ringGlass(when: illumination >= 0.5, in: Circle().stroke(lineWidth: 10))
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(.degrees(-90))
                                    .shadow(color: primaryColor.opacity(illumination), radius: 2 * illumination)
                                    .shadow(color: primaryColor.opacity(0.55 * illumination), radius: 5 * illumination)
                                    .animation(.easeInOut, value: primary.percentage)
                            }

                            // 3. Outer thin ring (only shown when user has selected both 5h and 7d limits)
                            if activeDisplayTypes.contains(.fiveHour) &&
                               activeDisplayTypes.contains(.sevenDay) {
                                // In custom mode, show placeholder ring even when data is nil
                                let sevenDayPercentage = data.sevenDay?.percentage ?? (UserSettings.shared.displayMode == .custom ? 0 : nil)

                                if let percentage = sevenDayPercentage {
                                    // 7-day background ring (gray)
                                    Circle()
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                                        .frame(width: 114, height: 114)

                                    if refreshState.isRefreshing {
                                        // Show outer ring animation for the corresponding type during refresh (counter-clockwise rotation)
                                        outerLoadingAnimation()
                                    } else {
                                        // 7-day progress arc (purple theme), with a softer
                                        // glow than the inner ring since the stroke is thinner.
                                        let sevenColor = colorForSevenDay(percentage)
                                        // Same glass treatment for the outer 7-day ring,
                                        // tuned for the thinner stroke (3pt can't hold as
                                        // many bands without muddying).
                                        let sevenGlass = LinearGradient(
                                            stops: [
                                                .init(color: .white.opacity(0.8), location: 0.0),
                                                .init(color: sevenColor, location: 0.3),
                                                .init(color: sevenColor.opacity(0.65), location: 0.65),
                                                .init(color: sevenColor.opacity(0.95), location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        let illumination = settings.ringIlluminationLevel
                                        Circle()
                                            .trim(from: 0, to: CGFloat(percentage) / 100.0)
                                            .stroke(
                                                sevenGlass,
                                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                            )
                                            .ringGlass(when: illumination >= 0.5, in: Circle().stroke(lineWidth: 3))
                                            .frame(width: 114, height: 114)
                                            .rotationEffect(.degrees(-90))
                                            .shadow(color: sevenColor.opacity(illumination), radius: 1.5 * illumination)
                                            .shadow(color: sevenColor.opacity(0.55 * illumination), radius: 4 * illumination)
                                            .animation(.easeInOut, value: percentage)
                                    }
                                }
                            }

                            // 4. Center display area: stacked percentages when both limits active
                            if activeDisplayTypes.contains(.fiveHour) &&
                               activeDisplayTypes.contains(.sevenDay) {
                                let fhPct = data.fiveHour?.percentage ?? 0
                                let sdPct = data.sevenDay?.percentage ?? 0
                                VStack(spacing: 1) {
                                    Text("\(Int(fhPct))%")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(colorForPercentage(fhPct))
                                    Text("\(Int(sdPct))%")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(colorForSevenDay(sdPct))
                                }
                            } else {
                                VStack(spacing: 2) {
                                    Text("\(Int(primary.percentage))%")
                                        .font(.system(size: 28, weight: .bold))
                                    Text(L.Usage.used)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 114)  // Fixed height to ensure consistent height with or without dual rings
                    .contentShape(Circle())  // Define clickable area as the entire circle
                    .onTapGesture {
                        // Tap the ring to refresh data
                        if refreshState.canRefresh && !refreshState.isRefreshing {
                            onMenuAction?(.refresh)
                        }
                    }
                    .onLongPressGesture(minimumDuration: 3.0) {
                        // Long press the ring to switch animation type
                        let allTypes = LoadingAnimationType.allCases
                        let currentIndex = allTypes.firstIndex(of: animationType) ?? 0
                        let nextIndex = (currentIndex + 1) % allTypes.count
                        animationType = allTypes[nextIndex]

                        // Show hint
                        withAnimation {
                            showAnimationTypeHint = true
                        }
                        // Hide hint after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showAnimationTypeHint = false
                            }
                        }
                    }

                    // Detail info - use different display methods based on number of user-selected display types
                    VStack(spacing: 8) {
                        let activeTypes = activeDisplayTypes

                        if activeTypes.count >= 3 {
                            // Scenario 3: 3 or more limits, use unified row display
                            VStack(spacing: 5) {
                                ForEach(activeTypes, id: \.self) { type in
                                    UnifiedLimitRow(
                                        type: type,
                                        data: data,
                                        showRemainingMode: showRemainingMode
                                    )
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showRemainingMode.toggle()
                                }
                                savedRemainingMode = showRemainingMode
                            }
                        } else if activeTypes.count == 2 {
                            // Scenario 2: user selected 2 limits, use unified row display
                            VStack(spacing: 5) {
                                ForEach(activeTypes, id: \.self) { type in
                                    UnifiedLimitRow(
                                        type: type,
                                        data: data,
                                        showRemainingMode: showRemainingMode
                                    )
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showRemainingMode.toggle()
                                }
                                savedRemainingMode = showRemainingMode
                            }
                        } else if activeTypes.count == 1 {
                            // Scenario 1: user selected only 1 limit, use large ring + 2-row info display
                            let singleType = activeTypes.first!

                            if singleType == .fiveHour, let fiveHour = data.fiveHour {
                                // Scenario 1a: show only 5-hour limit
                                VStack(spacing: 5) {
                                    InfoRow(
                                        icon: "clock.fill",
                                        title: L.Usage.fiveHourLimit,
                                        value: fiveHour.formattedResetsInHours
                                    )

                                    InfoRow(
                                        icon: "arrow.clockwise",
                                        title: L.Usage.resetTime,
                                        value: fiveHour.formattedResetTimeShort
                                    )
                                }
                            } else if singleType == .sevenDay, let sevenDay = data.sevenDay {
                                // Scenario 1b: show only 7-day limit (using purple)
                                VStack(spacing: 5) {
                                    InfoRow(
                                        icon: "calendar",
                                        title: L.Usage.sevenDayLimit,
                                        value: sevenDay.formattedResetsInDays,
                                        tintColor: .purple
                                    )

                                    InfoRow(
                                        icon: "calendar.badge.clock",
                                        title: L.Usage.resetDate,
                                        value: sevenDay.formattedResetDateLong,
                                        tintColor: .purple
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            } else {
                // Loading
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(L.Usage.loading)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            }

            // Animation type hint (long press the ring to switch)
            if showAnimationTypeHint {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text(L.LoadingAnimation.current(animationType.name))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(.horizontal, 12)
                .padding(.top, -8)  // Move up, consistent with update notification
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .scale))
            }

            Spacer()
        }
        .frame(width: 290, height: dynamicHeight)
        .id(localization.updateTrigger)  // Recreate view when language changes
        .onAppear {
            // Restore previously saved display mode
            showRemainingMode = savedRemainingMode
        }
        .onDisappear {
            // Clean up timer and reset state when view disappears
            stopRotationAnimation()
        }
        #if DEBUG
        .background(
            UserSettings.shared.debugKeepDetailWindowOpen ? Color.white : Color.clear
        )
        #endif
    }
}

// Conditional macOS-26 Liquid Glass overlay for the popover rings.
// The Glass material itself doesn't expose a continuous intensity knob, so the
// illumination slider gates it on/off at a 0.5 threshold while the surrounding
// shadows scale linearly.
private extension View {
    @ViewBuilder
    func ringGlass(when apply: Bool, in shape: some Shape) -> some View {
        if apply {
            self.glassEffect(in: shape)
        } else {
            self
        }
    }
}

// Preview
struct UsageDetailView_Previews: PreviewProvider {
    @State static var sampleData: UsageData? = UsageData(
        fiveHour: UsageData.LimitData(
            percentage: 45,
            resetsAt: Date().addingTimeInterval(3600 * 2.5)
        ),
        sevenDay: nil,
        opus: nil,
        sonnet: nil,
        extraUsage: nil
    )

    @State static var errorMsg: String? = nil
    @StateObject static var refreshState = RefreshState()

    static var previews: some View {
        UsageDetailView(
            usageData: $sampleData,
            errorMessage: $errorMsg,
            refreshState: refreshState
        )
    }
}
