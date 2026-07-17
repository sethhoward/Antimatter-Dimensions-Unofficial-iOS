//
//  TeresaPourButton.swift
//  AntiMatter
//
//  UIKit-backed hold-to-pour button. SwiftUI gestures don't cleanly model
//  continuous touch-down state, so we wrap a UIButton with explicit
//  touchDown/touchUp handlers and drive a CADisplayLink while held.
//  Each frame calls `onTick(deltaSeconds)`; release calls `onRelease`.
//

import SwiftUI
import UIKit

struct TeresaPourButton: UIViewRepresentable {
    let isCapped: Bool
    let onTick: (Double) -> Void
    let onRelease: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTick: onTick, onRelease: onRelease)
    }

    func makeUIView(context: Context) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        cfg.title = "Pour RM"
        cfg.baseForegroundColor = .white
        cfg.background.backgroundColor = UIColor.black
        cfg.background.strokeColor = UIColor(GameColor.teresa)
        cfg.background.strokeWidth = 2
        cfg.background.cornerRadius = 10
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)

        let btn = UIButton(configuration: cfg)
        btn.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        btn.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        btn.addTarget(context.coordinator, action: #selector(Coordinator.touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return btn
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        var cfg = uiView.configuration ?? UIButton.Configuration.plain()
        cfg.title = isCapped ? "Filled" : "Pour RM"
        cfg.baseForegroundColor = isCapped ? .white.withAlphaComponent(0.6) : .white
        cfg.background.backgroundColor = isCapped
            ? UIColor.black.withAlphaComponent(0.6)
            : UIColor.black
        uiView.configuration = cfg
        uiView.isEnabled = !isCapped
        context.coordinator.onTick = onTick
        context.coordinator.onRelease = onRelease
    }

    /// Expand the UIButton to fill the SwiftUI-assigned frame so the entire
    /// button background (not just the text label) receives touches. Without
    /// this override, UIButton sizes to its intrinsic content (title + insets)
    /// and taps outside the text fall through to the parent.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard let w = proposal.width, let h = proposal.height else { return nil }
        return CGSize(width: w, height: h)
    }

    final class Coordinator: NSObject {
        var onTick: (Double) -> Void
        var onRelease: () -> Void
        private var displayLink: CADisplayLink?
        private var lastFrameTime: CFTimeInterval = 0

        init(onTick: @escaping (Double) -> Void, onRelease: @escaping () -> Void) {
            self.onTick = onTick
            self.onRelease = onRelease
        }

        @objc func touchDown() {
            stopLink()
            lastFrameTime = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc func touchUp() {
            stopLink()
            onRelease()
        }

        @objc private func tick() {
            let now = CACurrentMediaTime()
            let dt = now - lastFrameTime
            lastFrameTime = now
            onTick(dt)
        }

        private func stopLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        deinit {
            stopLink()
        }
    }
}
