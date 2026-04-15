//
//  UpdateChecker.swift
//  Usage4Claude
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import AppKit

/// App update checker
/// Checks for new versions on GitHub Releases and prompts user to update
/// Supports both automatic and manual check modes
class UpdateChecker {
    // MARK: - Properties
    
    /// GitHub repository owner
    private let repoOwner = "arcanii"
    /// GitHub repository name
    private let repoName = "Usage4Claude-Arcanii"
    
    /// Current app version number
    /// - Returns: Version number read from Bundle, defaults to "1.0.0"
    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    // MARK: - Data Models
    
    /// GitHub Release data model
    /// Corresponds to the Release JSON structure returned by GitHub API
    struct GitHubRelease: Codable {
        /// Version tag (e.g., "v1.0.0")
        let tagName: String
        /// Release name
        let name: String
        /// Release notes content
        let body: String?
        /// Release page URL
        let htmlUrl: String
        /// Release assets list
        let assets: [Asset]
        
        /// Release asset (e.g., DMG file)
        struct Asset: Codable {
            /// Asset filename
            let name: String
            /// Download URL
            let browserDownloadUrl: String
            
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlUrl = "html_url"
            case assets
        }
    }
    
    // MARK: - Public Methods
    
    /// Background silent update check (no UI prompt)
    /// - Parameter completion: Completion callback, returns whether an update is available and the latest version
    func checkForUpdatesInBackground(completion: @escaping (Bool, String?) -> Void) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        
        guard let url = URL(string: urlString) else {
            completion(false, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Usage4Claude/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(false, nil)
                return
            }
            
            DispatchQueue.main.async {
                if error != nil {
                    completion(false, nil)
                    return
                }
                
                guard let data = data else {
                    completion(false, nil)
                    return
                }
                
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    let latestVersion = self.parseVersion(from: release.tagName)
                    let currentVersion = self.parseVersion(from: self.currentVersion)
                    
                    let hasUpdate = self.isNewerVersion(latest: latestVersion, current: currentVersion)
                    completion(hasUpdate, hasUpdate ? latestVersion : nil)
                } catch {
                    completion(false, nil)
                }
            }
        }
        
        task.resume()
    }
    
    /// Check for app updates
    /// - Parameter manually: Whether this is a manual check. Manual checks show all results (including no-update and errors); automatic checks only prompt when an update is available
    func checkForUpdates(manually: Bool = false) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        
        guard let url = URL(string: urlString) else {
            if manually {
                showError(message: L.Update.Error.invalidUrl)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Usage4Claude/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if error != nil {
                    if manually {
                        // Only show custom error message, not system error description
                        self.showError(message: L.Update.Error.network)
                    }
                    return
                }
                
                guard let data = data else {
                    if manually {
                        self.showError(message: L.Update.Error.noData)
                    }
                    return
                }
                
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    let latestVersion = self.parseVersion(from: release.tagName)
                    let currentVersion = self.parseVersion(from: self.currentVersion)
                    
                    if self.isNewerVersion(latest: latestVersion, current: currentVersion) {
                        self.showUpdateAlert(release: release)
                    } else {
                        if manually {
                            self.showNoUpdateAvailable()
                        }
                    }
                } catch {
                    if manually {
                        // Only show custom error message, not system error description
                        self.showError(message: L.Update.Error.parseFailed)
                    }
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - Private Methods
    
    /// Parse version number string
    /// - Parameter string: Raw version string (may contain "v" prefix)
    /// - Returns: Numeric version number only (e.g., "1.0.0")
    private func parseVersion(from string: String) -> String {
        return string.lowercased().replacingOccurrences(of: "v", with: "")
    }
    
    /// Compare version numbers (semantic versioning)
    /// - Parameters:
    ///   - latest: Latest version number
    ///   - current: Current version number
    /// - Returns: true if latest is newer than current
    /// - Note: Uses semantic versioning comparison rules (major.minor.patch)
    private func isNewerVersion(latest: String, current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        // Ensure at least 3 version components
        let latestPadded = (latestComponents + [0, 0, 0]).prefix(3)
        let currentPadded = (currentComponents + [0, 0, 0]).prefix(3)
        
        for (l, c) in zip(latestPadded, currentPadded) {
            if l > c {
                return true
            } else if l < c {
                return false
            }
        }
        
        return false
    }
    
    /// Show update prompt dialog
    /// - Parameter release: GitHub Release data
    private func showUpdateAlert(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = L.Update.newVersionTitle
        
        let latestVersion = parseVersion(from: release.tagName)
        var infoText = "\(L.Update.latestVersion): \(latestVersion)\n\(L.Update.currentVersion): \(currentVersion)\n\n"
        
        if let body = release.body, !body.isEmpty {
            infoText += formatReleaseNotes(body)
        } else {
            infoText += L.Update.viewReleasePage
        }
        
        alert.informativeText = infoText
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.Update.downloadButton)
        alert.addButton(withTitle: L.Update.remindLaterButton)
        alert.addButton(withTitle: L.Update.viewDetailsButton)
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Download update - open DMG download link
            if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                if let url = URL(string: dmgAsset.browserDownloadUrl) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                // If no DMG available, open Release page
                if let url = URL(string: release.htmlUrl) {
                    NSWorkspace.shared.open(url)
                }
            }
            
        case .alertThirdButtonReturn:
            // View details - open Release page
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
            
        default:
            // Remind later - do nothing
            break
        }
    }
    
    /// Show up-to-date dialog
    private func showNoUpdateAvailable() {
        let alert = NSAlert()
        alert.messageText = L.Update.upToDateTitle
        alert.informativeText = L.Update.upToDateMessage(currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.Update.okButton)
        alert.runModal()
    }
    
    /// Show error dialog
    /// - Parameter message: Error message content
    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = L.Update.checkFailedTitle
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.Update.confirmButton)
        alert.runModal()
    }
    
    /// Format Release Notes text
    /// - Parameter notes: Raw Release Notes
    /// - Returns: Formatted text, truncated if exceeding length limit
    /// - Note: Maximum length 300 characters
    private func formatReleaseNotes(_ notes: String) -> String {
        let maxLength = 300
        if notes.count > maxLength {
            let index = notes.index(notes.startIndex, offsetBy: maxLength)
            return String(notes[..<index]) + "...\n\n" + L.Update.viewDetailsHint
        }
        return notes
    }
}
