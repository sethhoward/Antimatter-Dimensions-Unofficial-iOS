//
//  ProgressBarView.swift
//  AntiMatter
//
//  Infinity progress bar at the bottom of the Dimensions tab.
//  Matches web: CSS transition-duration 0.1s on fill width.
//

import SwiftUI

struct ProgressBarView: View, Animatable {
    var fill: Double

    // JS-side progressFill is throttled to every 3rd tick (~10Hz). Animatable
    // lets SwiftUI interpolate between discrete values at display refresh, so
    // the bar glides continuously instead of snapping every 100ms.
    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    private static let bgColor: Color = .white.opacity(0.15)
    private static let cornerRadius: CGFloat = 4

    var body: some View {
        Canvas { ctx, size in
            let clamped = min(max(fill, 0), 1)
            let cr = Self.cornerRadius
            let fullRect = CGRect(origin: .zero, size: size)
            let fillW = size.width * clamped
            let fillRect = CGRect(x: 0, y: 0, width: fillW, height: size.height)

            // Background track
            ctx.fill(
                Path(roundedRect: fullRect, cornerRadius: cr),
                with: .color(Self.bgColor)
            )

            // Fill bar
            if fillW > 0 {
                ctx.fill(
                    Path(roundedRect: fillRect, cornerRadius: cr),
                    with: .color(GameColor.good)
                )
            }

            // Percentage text centered inside the fill area
            let label = String(format: "%.2f%%", clamped * 100)
            let text = Text(label)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.black)
            let resolved = ctx.resolve(text)
            let textSize = resolved.measure(in: CGSize(width: fillW, height: size.height))
            let textX = max(fillW / 2, textSize.width / 2 + 2)
            let textY = size.height / 2
            ctx.draw(resolved, at: CGPoint(x: textX, y: textY), anchor: .center)
        }
        .frame(height: 20)
    }
}
