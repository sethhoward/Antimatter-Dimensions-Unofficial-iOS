//
//  HoldRepeatModifier.swift
//  AntiMatter
//
//  Press-and-hold gesture modifier for "Max All" / "Buy Max" buttons.
//  Uses SwiftUI `.simultaneousGesture` so the underlying `Button`'s
//  press highlight (`configuration.isPressed`) keeps working — the
//  earlier UIKit overlay intercepted hit-testing and suppressed it.
//
//  Fire sequence on hold:
//    1. touch-down     → fire action once immediately
//    2. after 0.3s     → start repeat Timer at 0.15s interval
//    3. touch-up/cancel → invalidate Timer
//

import SwiftUI

extension View {
    /// Fires `action` on touch-down plus every `repeatInterval` while held
    /// (after `initialDelay`). Coexists with the underlying view's native
    /// tap behavior — Button presses register normally.
    ///
    /// - Parameters:
    ///   - isEnabled: When false, gestures + any in-flight timer are
    ///     suppressed. Pair with the button's own enabled gate.
    ///   - initialDelay: Wait before first repeat. Default 300ms.
    ///   - repeatInterval: Spacing between repeats. Default 150ms.
    ///   - action: Closure to fire on touch-down and each repeat tick.
    func onHoldRepeat(
        isEnabled: Bool = true,
        initialDelay: TimeInterval = 0.3,
        repeatInterval: TimeInterval = 0.15,
        action: @escaping () -> Void
    ) -> some View {
        modifier(HoldRepeatModifier(
            isEnabled: isEnabled,
            initialDelay: initialDelay,
            repeatInterval: repeatInterval,
            action: action
        ))
    }
}

private struct HoldRepeatModifier: ViewModifier {
    let isEnabled: Bool
    let initialDelay: TimeInterval
    let repeatInterval: TimeInterval
    let action: () -> Void

    @State private var state = HoldState()

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !state.isHeld else { return }
                    state.isHeld = true
                    action()
                    InteractionTracker.shared.recordTouch()
                    state.scheduleRepeat(
                        initialDelay: initialDelay,
                        repeatInterval: repeatInterval,
                        action: action
                    )
                }
                .onEnded { _ in
                    state.release()
                }
        )
    }
}

private final class HoldState {
    var isHeld = false
    private var timer: Timer?

    func scheduleRepeat(
        initialDelay: TimeInterval,
        repeatInterval: TimeInterval,
        action: @escaping () -> Void
    ) {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            guard let self, self.isHeld else { return }
            action()
            self.timer = Timer.scheduledTimer(withTimeInterval: repeatInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                if !self.isHeld {
                    self.stopTimer()
                    return
                }
                action()
            }
        }
    }

    func release() {
        isHeld = false
        stopTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stopTimer() }
}
