//
//  ToolbarButton.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Toolbar-style button component
struct ToolbarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.secondary.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())  // Expand tap area to entire background
        }
        .buttonStyle(.plain)
        .focusable(false)  // Remove focus effect
    }
}
