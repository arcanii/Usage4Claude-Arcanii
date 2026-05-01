//
//  WelcomeView.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// First launch welcome screen
/// Single page flow: Welcome -> All settings (authentication + theme + preview)
struct WelcomeView: View {
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared
    @State private var currentStep: WelcomeStep = .welcome
    @State private var sessionKey: String = ""
    @State private var isShowingPassword: Bool = false
    @State private var isFetchingOrgId: Bool = false
    @State private var fetchError: String?

    enum WelcomeStep {
        case welcome
        case setup
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView()
                case .setup:
                    SetupStepView(
                        sessionKey: $sessionKey,
                        isShowingPassword: $isShowingPassword
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom navigation buttons
            NavigationButtons(
                currentStep: currentStep,
                canProceed: canProceed,
                isFetchingOrgId: isFetchingOrgId,
                fetchError: fetchError,
                onBack: goToPreviousStep,
                onNext: goToNextStep,
                onSkip: skipSetup,
                onComplete: completeSetup
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(width: 550, height: 600)
        .id(localization.updateTrigger)
    }

    // MARK: - Computed Properties

    private var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .setup:
            return !sessionKey.isEmpty && settings.isValidSessionKey(sessionKey)
        }
    }

    // MARK: - Navigation Methods

    private func goToPreviousStep() {
        withAnimation {
            switch currentStep {
            case .setup:
                currentStep = .welcome
            case .welcome:
                break
            }
        }
    }

    private func goToNextStep() {
        withAnimation {
            switch currentStep {
            case .welcome:
                currentStep = .setup
            case .setup:
                completeSetup()
            }
        }
    }

    private func skipSetup() {
        settings.isFirstLaunch = false
        dismiss()
    }

    private func completeSetup() {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Show loading state
        isFetchingOrgId = true
        fetchError = nil

        // Fetch Organization ID and create account
        fetchOrganizationAndCreateAccount(sessionKey: trimmedKey) { success in
            DispatchQueue.main.async {
                isFetchingOrgId = false

                if success {
                    // Fetch successful, mark first launch as complete
                    settings.isFirstLaunch = false

                    // Post notification to trigger data refresh
                    NotificationCenter.default.post(name: .openSettings, object: nil)

                    // Close window
                    dismiss()
                } else {
                    // Fetch failed, show error but don't block user from continuing
                    // User can reconfigure later in settings
                    fetchError = L.Welcome.fetchOrgIdFailed

                    // Auto-close error and continue after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        settings.isFirstLaunch = false
                        dismiss()
                    }
                }
            }
        }
    }

    /// Fetch Organization and create account
    /// - Parameters:
    ///   - sessionKey: Session Key
    ///   - completion: Completion callback, returns whether it succeeded
    private func fetchOrganizationAndCreateAccount(sessionKey: String, completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let apiService = ClaudeAPIService()
            do {
                let organizations = try await apiService.fetchOrganizations(sessionKey: sessionKey)
                guard !organizations.isEmpty else {
                    completion(false)
                    return
                }
                for org in organizations {
                    let newAccount = Account(
                        sessionKey: sessionKey,
                        organizationId: org.uuid,
                        organizationName: org.name,
                        alias: nil
                    )
                    settings.addAccount(newAccount)
                }
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            if let icon = ImageHelper.createAppIcon(size: 120) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                    .shadow(radius: 10)
            }

            // Welcome text
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(L.Welcome.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("(Arcanii Mod)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Text(L.Welcome.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }
}

// MARK: - Setup Step (Combined Authentication + Display Options)

struct SetupStepView: View {
    @Binding var sessionKey: String
    @Binding var isShowingPassword: Bool
    @ObservedObject private var settings = UserSettings.shared

    // MARK: - Checkbox Helper Methods

    /// Determine if a checkbox should be disabled
    private func shouldDisableCheckbox(for limitType: LimitType) -> Bool {
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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Compact welcome info
                VStack(spacing: 8) {
                    if let icon = ImageHelper.createAppIcon(size: 48) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                    }

                    VStack(spacing: 2) {
                        Text(L.Welcome.title)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("(Arcanii Mod)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()
                    .padding(.vertical, 20)

                // Main settings area
                VStack(alignment: .leading, spacing: 20) {
                    // SessionKey setup
                    VStack(alignment: .leading, spacing: 12) {
                        // Title
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                            Text(L.Welcome.authenticationSetup)
                                .font(.headline)

                            Spacer()

                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(L.Welcome.multiAccountHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Browser login button (recommended)
                        Button(action: {
                            WebLoginWindowManager.shared.showLoginWindow { account in
                                // Auto-fill sessionKey after successful login
                                sessionKey = account.sessionKey
                            }
                        }) {
                            HStack {
                                Image(systemName: "globe")
                                Text(L.WebLogin.browserLoginRecommended)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        // Separator line
                        HStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                            Text(L.WebLogin.orManualInput)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .layoutPriority(1)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                        }

                        // Session Key input - horizontal
                        HStack(alignment: .top, spacing: 12) {
                            Text(L.Welcome.sessionKey)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 100, alignment: .leading)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if isShowingPassword {
                                        TextField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        SecureField(L.Welcome.sessionKeyPlaceholder, text: $sessionKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                    }

                                    Button(action: {
                                        isShowingPassword.toggle()
                                    }) {
                                        Image(systemName: isShowingPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Validation status
                                if !sessionKey.isEmpty {
                                    if settings.isValidSessionKey(sessionKey) {
                                        Label(L.Welcome.validFormat, systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Label(L.Welcome.invalidFormat, systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }

                                Text(L.Welcome.sessionKeyHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // Help button
                                Button(action: {
                                    if let url = URL(string: getGitHubReadmeURL(section: .initialSetup)) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "questionmark.circle")
                                        Text(L.Welcome.howToGetSessionKey)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // Theme settings
                    VStack(alignment: .leading, spacing: 12) {
                        // Title and preview
                        HStack(alignment: .top, spacing: 8) {
                            // Left side title
                            HStack(spacing: 8) {
                                Image(systemName: "paintpalette.fill")
                                    .font(.title3)
                                    .foregroundColor(.purple)
                                Text(L.Welcome.displayTitle)
                                    .font(.headline)
                            }

                            Spacer()

                            // Right side preview
                            VStack(alignment: .trailing, spacing: 6) {
                                MenuBarIconPreview()

                                // Menu bar icon hint link
                                Button(action: {
                                    if let url = URL(string: getGitHubReadmeURL(section: .faq)) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "questionmark.circle")
                                        Text(L.Welcome.menubarIconNotVisible)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Row 1: menu bar theme
                        HStack(alignment: .top, spacing: 12) {
                            Text(L.SettingsGeneral.menubarTheme)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 100, alignment: .leading)

                            HorizontalRadioGroup(
                                selection: $settings.iconStyleMode,
                                options: [
                                    (.colorTranslucent, L.IconStyle.colorTranslucent),
                                    (.monochrome, L.IconStyle.monochrome)
                                ]
                            )
                        }

                        // Row 2: display content - using checkboxes
                        HStack(alignment: .top, spacing: 12) {
                            Text(L.SettingsGeneral.displayContent)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 100, alignment: .leading)

                            VStack(alignment: .leading, spacing: 8) {
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
                                    .disabled(settings.iconDisplayMode == .unified)

                                    Toggle(isOn: $settings.showIconNumbers) {
                                        Text(L.Display.showNumber)
                                    }
                                    .toggleStyle(.checkbox)

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
                                }
                            }
                        }

                        // Row 3: display mode (smart/custom)
                        HStack(alignment: .top, spacing: 12) {
                            Text(L.DisplayOptions.displayModeLabel)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(width: 100, alignment: .leading)

                            VStack(alignment: .leading, spacing: 8) {
                                HorizontalRadioGroup(
                                    selection: $settings.displayMode,
                                    options: [
                                        (.smart, L.Welcome.smartModeRecommended),
                                        (.custom, L.Welcome.customSelection)
                                    ]
                                )

                                // Mode description
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text(settings.displayMode == .smart ?
                                         L.DisplayOptions.smartDisplayDescription :
                                         L.DisplayOptions.customDisplayDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                // Custom selection checkboxes - 3+2 two-row layout
                                if settings.displayMode == .custom {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(L.Welcome.selectLimits)
                                            .font(.caption)
                                            .fontWeight(.medium)

                                        VStack(alignment: .leading, spacing: 10) {
                                            // Row 1: 5-hour, 7-day, Extra Usage
                                            HStack(spacing: 16) {
                                                LimitTypeCheckbox(
                                                    limitType: .fiveHour,
                                                    isSelected: settings.customDisplayTypes.contains(.fiveHour),
                                                    isDisabled: shouldDisableCheckbox(for: .fiveHour)
                                                ) {
                                                    toggleLimitType(.fiveHour)
                                                }

                                                LimitTypeCheckbox(
                                                    limitType: .sevenDay,
                                                    isSelected: settings.customDisplayTypes.contains(.sevenDay),
                                                    isDisabled: shouldDisableCheckbox(for: .sevenDay)
                                                ) {
                                                    toggleLimitType(.sevenDay)
                                                }

                                                LimitTypeCheckbox(
                                                    limitType: .extraUsage,
                                                    isSelected: settings.customDisplayTypes.contains(.extraUsage),
                                                    isDisabled: shouldDisableCheckbox(for: .extraUsage)
                                                ) {
                                                    toggleLimitType(.extraUsage)
                                                }

                                                Spacer()
                                            }

                                            // Row 2: Opus Weekly, Sonnet Weekly
                                            HStack(spacing: 16) {
                                                LimitTypeCheckbox(
                                                    limitType: .opusWeekly,
                                                    isSelected: settings.customDisplayTypes.contains(.opusWeekly),
                                                    isDisabled: shouldDisableCheckbox(for: .opusWeekly)
                                                ) {
                                                    toggleLimitType(.opusWeekly)
                                                }

                                                LimitTypeCheckbox(
                                                    limitType: .sonnetWeekly,
                                                    isSelected: settings.customDisplayTypes.contains(.sonnetWeekly),
                                                    isDisabled: shouldDisableCheckbox(for: .sonnetWeekly)
                                                ) {
                                                    toggleLimitType(.sonnetWeekly)
                                                }

                                                Spacer()
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - GitHub README URL Helper

    /// README section enum
    private enum ReadmeSection {
        case initialSetup
        case faq
    }

    /// GitHub README URL for the requested section. The fork ships only the
    /// English README; the localized variants were removed in v1.5.x cleanup.
    private func getGitHubReadmeURL(section: ReadmeSection) -> String {
        let baseURL = "https://github.com/arcanii/Usage4Claude-Arcanii/blob/main"
        let anchor = section == .initialSetup ? "#initial-setup" : "#-faq"
        return "\(baseURL)/README.md\(anchor)"
    }
}

// MARK: - Horizontal Radio Group Component

/// Horizontal radio button group
struct HorizontalRadioGroup<T: Hashable>: View {
    let selection: Binding<T>
    let options: [(value: T, label: String)]
    let spacing: CGFloat

    init(selection: Binding<T>, options: [(value: T, label: String)], spacing: CGFloat = 16) {
        self.selection = selection
        self.options = options
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button(action: {
                    selection.wrappedValue = option.value
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: selection.wrappedValue == option.value ? "largecircle.fill.circle" : "circle")
                            .font(.body)
                            .foregroundColor(selection.wrappedValue == option.value ? .accentColor : .secondary)
                        Text(option.label)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)  // Disable keyboard focus
            }
        }
    }
}

// MARK: - Menu Bar Icon Preview

/// Menu bar icon preview component
/// Uses mock data to simulate the actual menu bar icon display
struct MenuBarIconPreview: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        // Simulated menu bar background
        HStack(spacing: 3) {
            Image(nsImage: getPreviewIcon())
                .resizable()
                .scaledToFit()
                .frame(height: 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(previewBackgroundColor)
        .cornerRadius(4)
    }

    /// Get preview icon (using createIcon method)
    private func getPreviewIcon() -> NSImage {
        let renderer = MenuBarIconRenderer(settings: settings)
        let mockData = createMockUsageData()

        // Use createIcon method so it correctly responds to iconDisplayMode
        return renderer.createIcon(usageData: mockData, button: nil)
    }

    /// Create mock usage data (66% usage)
    private func createMockUsageData() -> UsageData {
        let mockPercentage = 66.0

        return UsageData(
            fiveHour: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(3600)
            ),
            sevenDay: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(86400 * 3)
            ),
            opus: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(86400 * 5)
            ),
            sonnet: UsageData.LimitData(
                percentage: mockPercentage,
                resetsAt: Date().addingTimeInterval(86400 * 5)
            ),
            extraUsage: ExtraUsageData(
                enabled: true,
                used: mockPercentage,
                limit: 100.0,
                currency: "USD"
            )
        )
    }

    /// Preview background color (simulated menu bar)
    private var previewBackgroundColor: Color {
        // Return menu bar color based on system appearance
        if UsageColorScheme.isDarkMode {
            return Color(white: 0.2)  // Dark mode menu bar
        } else {
            return Color(white: 0.95)  // Light mode menu bar
        }
    }
}

// MARK: - Navigation Buttons

struct NavigationButtons: View {
    let currentStep: WelcomeView.WelcomeStep
    let canProceed: Bool
    let isFetchingOrgId: Bool
    let fetchError: String?
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Error message
            if let error = fetchError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Button row
            HStack(spacing: 12) {
                // Back button
                if currentStep != .welcome {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text(L.Welcome.back)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFetchingOrgId)
                }

                Spacer()

                // Skip button
                if currentStep != .setup {
                    Button(L.Welcome.skip, action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .disabled(isFetchingOrgId)
                }

                // Continue/Finish button
                Button(action: currentStep == .setup ? onComplete : onNext) {
                    HStack(spacing: 8) {
                        if isFetchingOrgId && currentStep == .setup {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                            Text(L.Welcome.configuring)
                        } else {
                            Text(currentStep == .setup ? L.Welcome.finish : L.Welcome.continue_)
                            if currentStep != .setup {
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                    .frame(maxWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || isFetchingOrgId)
            }
        }
    }
}
