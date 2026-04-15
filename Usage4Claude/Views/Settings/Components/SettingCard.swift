//
//  SettingCard.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Reusable settings card component
/// Provides a unified card layout with icon, title, content, and hint
struct SettingCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let hint: String
    @ViewBuilder let content: Content

    init(
        icon: String,
        iconColor: Color = .blue,
        title: String,
        hint: String = "",
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row: icon + title
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Divider()

            // Content area
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 32)

            // Hint info
            if !hint.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(hint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 32)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
