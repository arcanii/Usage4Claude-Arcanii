//
//  Usage4ClaudeWidgetBundle.swift
//  Usage4ClaudeWidget
//
//  Registry of every Widget kind shipped by this extension. WidgetKit
//  surfaces all of them in Edit Widgets…; the user picks which to install.
//
//  Roster:
//   1. Usage4ClaudeWidget    — small/medium rings (since v1.4.0)
//   2. LargeDashboardWidget   — systemLarge: all 5 limits at a glance
//   3. SparklineWidget        — small/medium: ring + 24h sparkline
//   4. DualSparklineWidget    — medium: 5h + 7d sparklines side-by-side
//   5. ExtraLargeWidget       — systemExtraLarge: full dashboard + sparkline strip
//
//  Control Center accessory families (.accessoryCircular/Rectangular/Inline)
//  were planned but are iOS/watchOS-only — not available on macOS Widget
//  extensions. Backlogged for if/when we add iOS continuity support.
//

import WidgetKit
import SwiftUI

@main
struct Usage4ClaudeWidgetBundle: WidgetBundle {
    var body: some Widget {
        Usage4ClaudeWidget()        // existing rings (small + medium)
        LargeDashboardWidget()      // #1 — systemLarge
        SparklineWidget()           // #2 — small/medium with sparkline
        DualSparklineWidget()       // #3 — medium dual-sparkline
        ExtraLargeWidget()          // #4 — systemExtraLarge
    }
}
