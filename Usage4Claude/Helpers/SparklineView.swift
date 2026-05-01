//
//  SparklineView.swift
//  Usage4Claude — Shared between main app and widget extension
//
//  Compact line chart for showing utilization history. Pure SwiftUI / Path
//  drawing — no AppKit, no Charts framework, so it compiles into the widget
//  extension's sandboxed target without dragging in main-app dependencies.
//
//  Values are percentages (0-100) in chronological order. The view scales the
//  X axis to fit the available width and the Y axis to the 0-100 range
//  (anchored — sparkline always starts from 0%, not from the data minimum,
//  so a 50% → 51% trickle reads correctly as "barely moving" rather than as
//  a dramatic spike).
//

import SwiftUI

public struct SparklineView: View {
    let values: [Double]
    let color: Color
    let lineWidth: CGFloat
    let showFill: Bool
    let showCurrentDot: Bool

    public init(
        values: [Double],
        color: Color,
        lineWidth: CGFloat = 1.5,
        showFill: Bool = true,
        showCurrentDot: Bool = true
    ) {
        self.values = values
        self.color = color
        self.lineWidth = lineWidth
        self.showFill = showFill
        self.showCurrentDot = showCurrentDot
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if values.count >= 2 {
                    if showFill {
                        fillPath(in: geo.size)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.30), color.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    linePath(in: geo.size)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                    if showCurrentDot, let last = values.last {
                        let lastPoint = pointFor(index: values.count - 1, value: last, in: geo.size)
                        Circle()
                            .fill(color)
                            .frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
                            .position(lastPoint)
                    }
                } else if let single = values.first {
                    // Single point — render a flat dotted line so the row
                    // doesn't appear empty.
                    let y = geo.size.height - (geo.size.height * CGFloat(clamped(single)) / 100.0)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(
                        color.opacity(0.4),
                        style: StrokeStyle(lineWidth: lineWidth, dash: [2, 3])
                    )
                }
            }
        }
    }

    // MARK: - Path construction

    private func linePath(in size: CGSize) -> Path {
        guard values.count >= 2 else { return Path() }
        var path = Path()
        for (i, v) in values.enumerated() {
            let p = pointFor(index: i, value: v, in: size)
            if i == 0 { path.move(to: p) }
            else { path.addLine(to: p) }
        }
        return path
    }

    private func fillPath(in size: CGSize) -> Path {
        guard values.count >= 2 else { return Path() }
        var path = linePath(in: size)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private func pointFor(index: Int, value: Double, in size: CGSize) -> CGPoint {
        // Even spacing across the X axis.
        let xStep = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        let x = CGFloat(index) * xStep
        // Y inverted (SwiftUI origin is top-left).
        let y = size.height - (size.height * CGFloat(clamped(value)) / 100.0)
        return CGPoint(x: x, y: y)
    }

    private func clamped(_ v: Double) -> Double {
        max(0, min(100, v))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rich curve") {
    SparklineView(
        values: [10, 15, 22, 30, 28, 35, 45, 60, 55, 70, 73],
        color: .green
    )
    .frame(width: 200, height: 40)
    .padding()
}

#Preview("Single point") {
    SparklineView(values: [42], color: .purple)
        .frame(width: 200, height: 40)
        .padding()
}

#Preview("Empty") {
    SparklineView(values: [], color: .pink)
        .frame(width: 200, height: 40)
        .padding()
}
#endif
