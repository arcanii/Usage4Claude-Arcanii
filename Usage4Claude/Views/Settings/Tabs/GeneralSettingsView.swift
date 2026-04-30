//
//  GeneralSettingsView.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import ServiceManagement

/// General settings page
/// Uses card layout with launch at login, display settings, refresh settings, and language settings
struct GeneralSettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Display settings card
                SettingCard(
                    icon: "gauge.with.dots.needle.0percent",
                    iconColor: .blue,
                    title: L.SettingsGeneral.displaySection,
                    hint: L.SettingsGeneral.menubarHint
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Icon style selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.SettingsGeneral.menubarTheme)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $settings.iconStyleMode) {
                                ForEach(IconStyleMode.allCases, id: \.self) { mode in
                                    Text(mode.localizedName).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                            .focusable(false)
                            
                            // Description text
                            if !settings.iconStyleMode.description.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text(settings.iconStyleMode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, 20)
                            }
                        }
                        
                        Divider()
                        
                        // Display content selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.SettingsGeneral.displayContent)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            HStack(spacing: 16) {
                                Toggle(isOn: Binding(
                                    get: { settings.iconDisplayMode == .iconOnly || settings.iconDisplayMode == .both },
                                    set: { showIcon in
                                        let showPercentage = settings.iconDisplayMode == .percentageOnly || settings.iconDisplayMode == .both
                                        if showIcon && showPercentage {
                                            settings.iconDisplayMode = .both
                                        } else if showIcon {
                                            settings.iconDisplayMode = .iconOnly
                                        } else if showPercentage {
                                            settings.iconDisplayMode = .percentageOnly
                                        } else {
                                            settings.iconDisplayMode = .percentageOnly
                                        }
                                    }
                                )) {
                                    Text(L.Display.showIcon)
                                }
                                .toggleStyle(.checkbox)
                                .focusable(false)
                                .disabled(settings.iconDisplayMode == .unified)

                                Toggle(isOn: Binding(
                                    get: { settings.iconDisplayMode == .percentageOnly || settings.iconDisplayMode == .both },
                                    set: { showPercentage in
                                        let showIcon = settings.iconDisplayMode == .iconOnly || settings.iconDisplayMode == .both
                                        if showIcon && showPercentage {
                                            settings.iconDisplayMode = .both
                                        } else if showPercentage {
                                            settings.iconDisplayMode = .percentageOnly
                                        } else if showIcon {
                                            settings.iconDisplayMode = .iconOnly
                                        } else {
                                            settings.iconDisplayMode = .iconOnly
                                        }
                                    }
                                )) {
                                    Text(L.Display.showPercentage)
                                }
                                .toggleStyle(.checkbox)
                                .focusable(false)
                                .disabled(settings.iconDisplayMode == .unified)

                                Toggle(isOn: $settings.showIconNumbers) {
                                    Text(L.Display.showNumber)
                                }
                                .toggleStyle(.checkbox)
                                .focusable(false)

                                Toggle(isOn: Binding(
                                    get: { settings.iconDisplayMode == .unified },
                                    set: { isUnified in
                                        if isUnified {
                                            settings.iconDisplayMode = .unified
                                        } else {
                                            settings.iconDisplayMode = .percentageOnly
                                        }
                                    }
                                )) {
                                    Text(L.Display.unified)
                                }
                                .toggleStyle(.checkbox)
                                .focusable(false)
                            }
                        }
                    }
                }

                // Display options card
                SettingCard(
                    icon: "rectangle.3.group",
                    iconColor: .purple,
                    title: L.DisplayOptions.title,
                    hint: settings.displayMode == .smart ? L.DisplayOptions.smartDisplayDescription : L.DisplayOptions.customDisplayDescription
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Display mode selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.DisplayOptions.displayModeLabel)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            Picker("", selection: $settings.displayMode) {
                                Text(L.DisplayOptions.smartDisplay).tag(DisplayMode.smart)
                                Text(L.DisplayOptions.customDisplay).tag(DisplayMode.custom)
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                            .focusable(false)
                        }

                        // Custom selection (only shown in custom mode)
                        if settings.displayMode == .custom {
                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                Text(L.DisplayOptions.selectLimitTypes)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(LimitType.allCases, id: \.self) { limitType in
                                        LimitTypeCheckbox(
                                            limitType: limitType,
                                            isSelected: settings.customDisplayTypes.contains(limitType),
                                            isDisabled: shouldDisableCheckbox(for: limitType)
                                        ) {
                                            toggleLimitType(limitType)
                                        }
                                    }
                                }
                                .padding(.leading, 20)

                                // Constraint hint info
                                if hasOnlyOneCircularIcon {
                                    HStack(alignment: .top, spacing: 4) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                        Text(L.DisplayOptions.circularIconConstraint)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.leading, 20)
                                }

                                // Theme availability hint
                                if !canUseColoredTheme {
                                    HStack(alignment: .top, spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                        Text(L.DisplayOptions.coloredThemeUnavailable)
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                        }
                    }
                }

                // Refresh settings card
                SettingCard(
                    icon: "clock.arrow.trianglehead.2.counterclockwise.rotate.90",
                    iconColor: .green,
                    title: L.SettingsGeneral.refreshSection,
                    hint: settings.refreshMode == .smart ? L.SettingsGeneral.refreshHintSmart : L.SettingsGeneral.refreshHintFixed
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Refresh mode selection
                        Picker("", selection: $settings.refreshMode) {
                            ForEach(RefreshMode.allCases, id: \.self) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .focusable(false)
                        
                        // Fixed frequency selection (only shown when fixed mode is selected)
                        if settings.refreshMode == .fixed {
                            HStack {
                                Text(L.SettingsGeneral.refreshInterval)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $settings.refreshInterval) {
                                    ForEach(RefreshInterval.allCases, id: \.rawValue) { interval in
                                        Text(interval.localizedName).tag(interval.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                            .padding(.leading, 20)
                        }
                    }
                }
                
                // Notification settings card
                SettingCard(
                    icon: "bell.badge",
                    iconColor: .red,
                    title: L.SettingsNotification.section,
                    hint: L.SettingsNotification.hint
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("", isOn: $settings.notificationsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .focusable(false)
                                .labelsHidden()
                            Text(L.SettingsNotification.enable)
                            Spacer()
                        }
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(L.SettingsNotification.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Appearance settings card
                SettingCard(
                    icon: "circle.lefthalf.filled",
                    iconColor: .indigo,
                    title: L.SettingsGeneralAppearance.section,
                    hint: L.SettingsGeneralAppearance.hint
                ) {
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .focusable(false)
                }

                // Time format settings card
                SettingCard(
                    icon: "clock",
                    iconColor: .cyan,
                    title: L.SettingsGeneralTimeFormat.section,
                    hint: L.SettingsGeneralTimeFormat.hint
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $settings.timeFormatPreference) {
                            ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                                Text(format.localizedName).tag(format)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .focusable(false)

                        // Current time preview
                        HStack(spacing: 4) {
                            Text(L.SettingsGeneralTimeFormat.preview + ":")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(timePreviewString)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .padding(.leading, 20)
                    }
                }

                // Language settings card
                SettingCard(
                    icon: "globe",
                    iconColor: .orange,
                    title: L.SettingsGeneral.languageSection,
                    hint: L.SettingsGeneral.languageHint
                ) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.localizedName).tag(lang)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .focusable(false)
                }

                // Launch at login settings card
                SettingCard(
                    icon: "power",
                    iconColor: .orange,
                    title: L.SettingsGeneral.launchSection,
                    hint: L.SettingsGeneral.launchHint
                ) {
                    HStack {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .focusable(false)
                            .labelsHidden()

                        Text(L.SettingsGeneral.launchAtLogin)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                                .font(.caption)
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Reset button
                HStack {
                    Spacer()
                    Button(L.SettingsGeneral.resetButton) {
                        settings.resetToDefaults()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)

                // MARK: - Debug mode section (only visible in Debug builds)

                #if DEBUG
                // Debug settings card
                SettingCard(
                    icon: "ladybug.fill",
                    iconColor: .orange,
                    title: "调试模式",
                    hint: "切换场景后，点击刷新按钮查看效果"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Enable debug mode switch
                        HStack {
                            Toggle("", isOn: $settings.debugModeEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .focusable(false)
                                .labelsHidden()

                            Text("启用调试模式")

                            Spacer()

                            Text("仅Debug编译可见")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Percentage sliders (only shown when debug mode is enabled)
                        if settings.debugModeEnabled {
                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 12) {
                                // 5-hour limit
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("5小时限制百分比：")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.debugFiveHourPercentage))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.green)
                                    }
                                    Slider(value: $settings.debugFiveHourPercentage, in: 0...100, step: 1)
                                        .tint(.green)
                                }

                                // 7-day limit
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("7天限制百分比：")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.debugSevenDayPercentage))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.purple)
                                    }
                                    Slider(value: $settings.debugSevenDayPercentage, in: 0...100, step: 1)
                                        .tint(.purple)
                                }

                                // Extra Usage limit
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Extra Usage 百分比：")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.debugExtraUsagePercentage))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.pink)
                                    }
                                    Slider(value: $settings.debugExtraUsagePercentage, in: 0...100, step: 1)
                                        .tint(.pink)
                                }

                                // Opus Weekly limit
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Opus Weekly 百分比：")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.debugOpusPercentage))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.orange)
                                    }
                                    Slider(value: $settings.debugOpusPercentage, in: 0...100, step: 1)
                                        .tint(.orange)
                                }

                                // Sonnet Weekly limit
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Sonnet Weekly 百分比：")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.debugSonnetPercentage))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                    }
                                    Slider(value: $settings.debugSonnetPercentage, in: 0...100, step: 1)
                                        .tint(.blue)
                                }
                            }
                            .padding(.leading, 20)
                        }

                        // Show all shape icons individually switch
                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Toggle("", isOn: $settings.debugShowAllShapesIndividually)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .focusable(false)
                                .labelsHidden()

                            Text("形状图标可单独显示")
                                .font(.subheadline)

                            Spacer()

                            Text("方便截图")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Keep detail window open switch
                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Toggle("", isOn: $settings.debugKeepDetailWindowOpen)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .focusable(false)
                                .labelsHidden()

                            Text("保持详情窗口始终打开")
                                .font(.subheadline)

                            Spacer()

                            Text("背景变为不透明纯白色")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    }
                }
                #endif
            }
            .padding()
        }
        .onAppear {
            // Sync status when settings page opens
            settings.syncLaunchAtLoginStatus()
            
            // Listen for error notifications
            NotificationCenter.default.addObserver(
                forName: .launchAtLoginError,
                object: nil,
                queue: .main
            ) { notification in
                handleLaunchError(notification)
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(L.LaunchAtLogin.errorTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text(L.Update.okButton))
            )
        }
    }
    
    // MARK: - Computed Properties

    /// Time preview string
    private var timePreviewString: String {
        let now = Date()
        return TimeFormatHelper.formatTimeOnly(now)
    }

    /// Status icon
    private var statusIcon: String {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return "checkmark.circle.fill"
        case .requiresApproval:
            return "exclamationmark.circle.fill"
        case .notRegistered:
            return "circle"
        case .notFound:
            return "xmark.circle.fill"
        @unknown default:
            // Treat unknown status as disabled; real status will be synced on onAppear
            return "circle"
        }
    }
    
    /// Status color
    private var statusColor: Color {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return .green
        case .requiresApproval:
            return .orange
        case .notRegistered:
            return .secondary
        case .notFound:
            return .red
        @unknown default:
            // Treat unknown status as disabled
            return .secondary
        }
    }
    
    /// Status text
    private var statusText: String {
        switch settings.launchAtLoginStatus {
        case .enabled:
            return L.LaunchAtLogin.statusEnabled
        case .requiresApproval:
            return L.LaunchAtLogin.statusRequiresApproval
        case .notRegistered:
            return L.LaunchAtLogin.statusDisabled
        case .notFound:
            return L.LaunchAtLogin.statusNotFound
        @unknown default:
            // Treat unknown status as disabled
            return L.LaunchAtLogin.statusDisabled
        }
    }
    
    // MARK: - Error Handling

    /// Handle launch at login error
    private func handleLaunchError(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let error = userInfo["error"] as? Error,
              let operation = userInfo["operation"] as? String else {
            return
        }

        let operationType = operation == "enable" ? L.LaunchAtLogin.errorEnable : L.LaunchAtLogin.errorDisable
        errorMessage = "\(operationType)\n\n\(error.localizedDescription)"
        showErrorAlert = true
    }

    // MARK: - Display Options Helpers

    /// Check if only one circular icon remains
    private var hasOnlyOneCircularIcon: Bool {
        let circularTypes: Set<LimitType> = [.fiveHour, .sevenDay]
        let selectedCircular = settings.customDisplayTypes.intersection(circularTypes)
        return selectedCircular.count == 1
    }

    /// Check if colored theme can be used
    private var canUseColoredTheme: Bool {
        // All limit types now support colored display
        // Colored theme can be used as long as any limit type is selected
        return !settings.customDisplayTypes.isEmpty
    }

    /// Determine if a checkbox should be disabled
    private func shouldDisableCheckbox(for limitType: LimitType) -> Bool {
        #if DEBUG
        // In Debug mode, if "show all shapes individually" is enabled, allow unchecking all limits
        if settings.debugShowAllShapesIndividually {
            return false
        }
        #endif

        let circularTypes: Set<LimitType> = [.fiveHour, .sevenDay]

        // Disable if this is the last selected circular icon
        if circularTypes.contains(limitType) {
            let selectedCircular = settings.customDisplayTypes.intersection(circularTypes)
            return selectedCircular.count == 1 && selectedCircular.contains(limitType)
        }

        return false
    }

    /// Toggle limit type selection state
    private func toggleLimitType(_ limitType: LimitType) {
        if settings.customDisplayTypes.contains(limitType) {
            // Check if deselection is allowed
            if !shouldDisableCheckbox(for: limitType) {
                settings.customDisplayTypes.remove(limitType)
            }
        } else {
            settings.customDisplayTypes.insert(limitType)
        }
    }
}

// MARK: - Limit Type Checkbox Component

/// Limit type checkbox component
struct LimitTypeCheckbox: View {
    let limitType: LimitType
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            if !isDisabled {
                onToggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isDisabled ? .secondary : (isSelected ? .blue : .primary))
                    .font(.body)

                HStack(spacing: 6) {
                    // Limit type icon
                    limitTypeIcon
                        .font(.caption)

                    // Limit type name
                    Text(limitType.displayName)
                        .foregroundColor(isDisabled ? .secondary : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? "At least one circular icon must be selected" : "")
        .fixedSize()
    }

    @ViewBuilder
    private var limitTypeIcon: some View {
        // Draw icon using Canvas, same as the detail view
        Canvas { context, canvasSize in
            let lineWidth: CGFloat = 1.8
            let path = shapePath(for: limitType, in: CGRect(origin: .zero, size: canvasSize))

            // Draw background border
            context.stroke(path, with: .color(Color.gray.opacity(0.3)), lineWidth: lineWidth)

            // Draw full progress ring (100%)
            context.stroke(path, with: .color(iconColor(for: limitType)), lineWidth: lineWidth)
        }
        .frame(width: 14, height: 14)
    }

    private func shapePath(for type: LimitType, in rect: CGRect) -> Path {
        return IconShapePaths.pathForLimitType(type, in: rect)
    }

    private func iconColor(for type: LimitType) -> Color {
        switch type {
        case .fiveHour: return .green
        case .sevenDay: return .purple
        case .extraUsage: return .pink
        case .opusWeekly: return .orange
        case .sonnetWeekly: return .blue
        }
    }
}

/// Authentication settings page
/// Uses card layout for configuring Organization ID and Session Key
