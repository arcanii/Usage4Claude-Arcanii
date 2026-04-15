//
//  InfoRow.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Info row component
/// Displays a single row of information with icon, title, and value
struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var tintColor: Color = .blue  // Customizable icon color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(tintColor)  // Use custom color
                .frame(width: 8)
                .font(.system(size: 12))  // Icon size

            Text(title)
                .font(.system(size: 12))  // First column text size
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12))  // Second column text size
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)  // Row height
        .padding(.horizontal, 12) // Row width
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
