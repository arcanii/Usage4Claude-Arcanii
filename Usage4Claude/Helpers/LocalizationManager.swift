//
//  LocalizationManager.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-11-05.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog

/// Localization manager
/// Responsible for listening to language changes and triggering view updates, enabling instant language switching
class LocalizationManager: ObservableObject {
    /// Singleton instance
    static let shared = LocalizationManager()
    
    /// Update trigger, incremented on language change, used to force view recreation
    @Published var updateTrigger: Int = 0
    
    /// Notification observer
    private var cancellable: AnyCancellable?
    
    private init() {
        // Listen for language change notifications
        cancellable = NotificationCenter.default
            .publisher(for: .languageChanged)
            .sink { [weak self] _ in
                // Increment trigger on language change; all views using .id(updateTrigger) will be recreated
                self?.updateTrigger += 1
                Logger.localization.debug("语言已切换，触发视图更新")
            }
    }
    
    deinit {
        cancellable?.cancel()
    }
}
