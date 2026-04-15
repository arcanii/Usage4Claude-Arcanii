//
//  ImageHelper.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit

/// Image processing helper utility
/// Provides app icon creation, caching, and related functionality
enum ImageHelper {
    // MARK: - App Icon

    /// Create app icon (non-template mode)
    /// - Parameter size: Icon size
    /// - Returns: App icon at the specified size, or nil if unable to load
    static func createAppIcon(size: CGFloat) -> NSImage? {
        guard let appIcon = NSImage(named: "AppIcon") else { return nil }
        guard let iconCopy = appIcon.copy() as? NSImage else { return nil }
        iconCopy.isTemplate = false
        iconCopy.size = NSSize(width: size, height: size)
        return iconCopy
    }

    /// Create app icon (non-template mode, with specified width and height)
    /// - Parameters:
    ///   - width: Icon width
    ///   - height: Icon height
    /// - Returns: App icon at the specified dimensions, or nil if unable to load
    static func createAppIcon(width: CGFloat, height: CGFloat) -> NSImage? {
        guard let appIcon = NSImage(named: "AppIcon") else { return nil }
        guard let iconCopy = appIcon.copy() as? NSImage else { return nil }
        iconCopy.isTemplate = false
        iconCopy.size = NSSize(width: width, height: height)
        return iconCopy
    }

    // MARK: - System Images

    /// Create system symbol image
    /// - Parameters:
    ///   - systemName: SF Symbols name
    ///   - size: Image size
    ///   - weight: Symbol weight
    /// - Returns: Created system image, or nil if unable to load
    static func createSystemImage(
        systemName: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
