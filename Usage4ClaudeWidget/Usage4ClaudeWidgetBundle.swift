//
//  Usage4ClaudeWidgetBundle.swift
//  Usage4ClaudeWidget
//
//  WidgetBundle entry point. Just one widget for now (the Claude Usage rings).
//  AppIntent and Control widget stubs Xcode generates by default are unused —
//  no configuration UI needed; the widget reads everything from the App Group
//  snapshot the main app writes on each successful fetch.
//

import WidgetKit
import SwiftUI

@main
struct Usage4ClaudeWidgetBundle: WidgetBundle {
    var body: some Widget {
        Usage4ClaudeWidget()
    }
}
