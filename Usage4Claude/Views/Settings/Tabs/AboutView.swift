//
//  AboutView.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// About page
/// Displays app information, version number, and related links
struct AboutView: View {
    /// Read app version from Bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // App icon (not using template mode)
            if let icon = ImageHelper.createAppIcon(size: 100) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .cornerRadius(20)
                    .shadow(radius: 5)
            }
            
            // App name and version
            VStack(spacing: 4) {
                Text("Usage4Claude")
                    .font(.title)
                    .fontWeight(.bold)
                Text("(Arcanii Mod)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(L.SettingsAbout.version(appVersion))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Description
            Text(L.SettingsAbout.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
                .padding(.horizontal, 60)
            
            // Info list
            VStack(alignment: .leading, spacing: 12) {
                AboutInfoRow(icon: "person.fill", title: L.SettingsAbout.developer, value: "arcanii")
                AboutInfoRow(icon: "doc.text", title: L.SettingsAbout.license, value: L.SettingsAbout.licenseValue)
            }
            
            Spacer()
            
            // Link buttons
            VStack(spacing: 8) {
                Button(action: {
                    if let url = URL(string: "https://github.com/arcanii/Usage4Claude-Arcanii") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "link")
                        Text(L.SettingsAbout.github)
                    }
                    .frame(minWidth: 200)
                }
                .focusable(false)
            }
            
            // Copyright info
            Text(L.SettingsAbout.copyright)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

