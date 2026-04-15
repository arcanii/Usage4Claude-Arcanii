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
    /// Whether an update is available (used to display text and badge)
    @Binding var hasAvailableUpdate: Bool
    /// Whether the update badge should be shown (only displayed when user hasn't acknowledged)
    @Binding var shouldShowUpdateBadge: Bool
    
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
        case coffee
        case quit
        case refresh
    }
    
    // Animation state (passed from outside to avoid resetting on each view rebuild)
    @State var rotationAngle: Double = 0
    @State var animationTimer: Timer?
    // Show animation type switch hint
    @State private var showAnimationTypeHint = false
    // Show update notification
    @State private var showUpdateNotification = false
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

        // Use unified dynamic calculation to ensure consistent bottom margin
        // Base height: total height of fixed content including ring, title, top/bottom margins
        // Actual row height: text(12pt) + vertical padding(12pt) + background height ≈ 26pt
        // Row spacing: 5pt
        let baseHeight: CGFloat = 190
        let rowHeight: CGFloat = 26
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

                        // Check for updates menu item (displays different style based on update availability)
                        if hasAvailableUpdate {
                            Button(action: { onMenuAction?(.checkForUpdates) }) {
                                Label {
                                    Text(createUpdateMenuText())
                                } icon: {
                                    Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                                }
                            }
                        } else {
                            Button(action: { onMenuAction?(.checkForUpdates) }) {
                                Label(L.Menu.checkUpdates, systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        Button(action: { onMenuAction?(.about) }) {
                            Label(L.Menu.about, systemImage: "info.circle")
                        }
                        Divider()
                        Button(action: { onMenuAction?(.webUsage) }) {
                            Label(L.Menu.webUsage, systemImage: "safari")
                        }
                        Button(action: { onMenuAction?(.coffee) }) {
                            Label(L.Menu.coffee, systemImage: "cup.and.saucer")
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

                    // Badge (red dot) - only shown when user hasn't acknowledged
                    if shouldShowUpdateBadge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .offset(x: 5, y: -5)
                    }
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
                                // 2. Main progress arc (based on user-selected limit type)
                                Circle()
                                    .trim(from: 0, to: CGFloat(primary.percentage) / 100.0)
                                    .stroke(
                                        colorForPrimaryByActiveTypes(data: data, activeTypes: activeDisplayTypes),
                                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                    )
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(.degrees(-90))
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
                                        // 7-day progress arc (purple theme)
                                        Circle()
                                            .trim(from: 0, to: CGFloat(percentage) / 100.0)
                                            .stroke(
                                                colorForSevenDay(percentage),
                                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                            )
                                            .frame(width: 114, height: 114)
                                            .rotationEffect(.degrees(-90))
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

            // Update notification hint (displayed below the ring)
            if showUpdateNotification {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    rainbowText(L.Update.Notification.available)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 12)
                .padding(.top, -8)  // Move up
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
            // If there's an update notification message, show notification
            if refreshState.notificationMessage != nil {
                withAnimation {
                    showUpdateNotification = true
                }
                // Hide notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showUpdateNotification = false
                    }
                }
            }
        }
        .onChange(of: refreshState.notificationMessage) { message in
            // Listen for notification message changes
            if message != nil {
                withAnimation {
                    showUpdateNotification = true
                }
                // Hide notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showUpdateNotification = false
                    }
                }
            } else {
                withAnimation {
                    showUpdateNotification = false
                }
            }
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
    @State static var hasUpdate = false
    @State static var shouldShowBadge = false

    static var previews: some View {
        UsageDetailView(
            usageData: $sampleData,
            errorMessage: $errorMsg,
            refreshState: refreshState,
            hasAvailableUpdate: $hasUpdate,
            shouldShowUpdateBadge: $shouldShowBadge
        )
    }
}
