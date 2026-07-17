//
//  NewsTickerView.swift
//  AntiMatter
//
//  Scrolling news ticker — matches web Modern UI NewsTicker.vue behavior.
//  Messages selected in JS, scroll driven by CABasicAnimation (render-server
//  smooth at native display rate, independent of SwiftUI's refresh cycle).
//

import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

struct NewsTickerView: View {
    let engine: GameEngine
    let height: CGFloat

    var body: some View {
        ScrollingTickerRepresentable(engine: engine, isCompact: height <= 24, fontSize: height > 24 ? 14 : 12)
            .frame(height: height)
    }
}

// MARK: - UIViewRepresentable

private struct ScrollingTickerRepresentable: UIViewRepresentable {
    let engine: GameEngine
    let isCompact: Bool
    let fontSize: CGFloat

    func makeUIView(context: Context) -> ScrollingTickerUIView {
        let view = ScrollingTickerUIView(fontSize: fontSize, isCompact: isCompact)
        view.engine = engine
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ScrollingTickerUIView, context: Context) {
        // Engine ref is stable; nothing to update per-cycle.
    }
}

// MARK: - UIKit ticker view (CABasicAnimation-driven)

private final class ScrollingTickerUIView: UIView, CAAnimationDelegate {
    weak var engine: GameEngine?

    private let label = UILabel()
    private let isCompact: Bool
    private var currentId: String = ""
    private var currentHasOnClick: Bool = false
    private var scrollWork: DispatchWorkItem?
    private var hasStarted = false
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?

    init(fontSize: CGFloat, isCompact: Bool) {
        self.isCompact = isCompact
        super.init(frame: .zero)

        label.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.numberOfLines = 1
        addSubview(label)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        // Cancel animation on background, restart on foreground — prevents
        // the render server from compositing the CABasicAnimation while the
        // app is inactive, and avoids stale DispatchWorkItem firing mid-suspend.
        bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelScroll() }
        fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.hasStarted, self.window != nil else { return }
            self.loadNextMessage()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let bgObserver { NotificationCenter.default.removeObserver(bgObserver) }
        if let fgObserver { NotificationCenter.default.removeObserver(fgObserver) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !hasStarted && bounds.width > 0 {
            hasStarted = true
            loadNextMessage()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { cancelScroll() }
    }

    // MARK: - Scroll loop

    private func loadNextMessage() {
        cancelScroll()
        engine?.requestNextNewsMessage { [weak self] id, text, onClick in
            guard let self, self.window != nil else { return }
            self.currentId = id
            self.currentHasOnClick = onClick

            self.label.text = text
            self.label.sizeToFit()

            // Position off-screen right
            let containerW = self.bounds.width
            self.label.frame.origin = CGPoint(x: containerW, y: (self.bounds.height - self.label.bounds.height) / 2)

            // Delay before scroll — iPhone gets a longer pause
            let delay: TimeInterval = self.isCompact ? 6.0 : 1.0
            let work = DispatchWorkItem { [weak self] in self?.beginScroll() }
            self.scrollWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func beginScroll() {
        guard window != nil else { return }
        let containerW = bounds.width
        let textW = label.bounds.width
        guard textW > 0 else { loadNextMessage(); return }

        let speed = max(engine?.newsSpeed ?? 1.0, 0.1) * 100
        let effectiveSpeed = isCompact ? speed * 0.6 : speed
        let totalDistance = containerW + textW
        let duration = Double(totalDistance) / effectiveSpeed

        // Destination: fully off-screen left
        let endX = -textW

        // CABasicAnimation on position.x — runs on the render server at native refresh rate
        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = label.center.x
        anim.toValue = endX + textW / 2  // center-based
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        anim.delegate = self
        label.layer.add(anim, forKey: "scroll")

        // Update model position to match end state
        label.frame.origin.x = endX
    }

    // CAAnimationDelegate — scroll finished
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        label.layer.removeAllAnimations()
        guard flag else { return }
        engine?.newsMessageScrolled(currentId)
        loadNextMessage()
    }

    private func cancelScroll() {
        scrollWork?.cancel()
        scrollWork = nil
        label.layer.removeAllAnimations()
    }

    // MARK: - Tap

    @objc private func handleTap() {
        guard currentHasOnClick else { return }
        engine?.newsMessageClicked(currentId) { [weak self] updated in
            if let updated { self?.label.text = updated }
        }
    }
}
