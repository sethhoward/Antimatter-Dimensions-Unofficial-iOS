//
//  KeyCommandHost.swift
//  AntiMatter
//
//  Mounts the hardware-keyboard `UIKeyCommand` table for the app. One
//  instance, parked invisibly in `ContentView` (iPad) + `PhoneShell`
//  (iPhone); becomes first responder so bindings fire while no text field
//  is focused.
//
//  Implementation notes:
//
//  - Uses a `UIView` subclass (not `UIViewController`) — UIView supports
//    `canBecomeFirstResponder` and `keyCommands` directly, and is simpler
//    to reason about inside SwiftUI's responder chain than the controller
//    bridge.
//
//  - Must NOT set `isUserInteractionEnabled = false`. Doing so prevents
//    `becomeFirstResponder()` from succeeding and the bindings silently
//    disappear from the Cmd-Hold HUD on iPad Magic Keyboard. We rely on
//    the tiny (1x1) frame parked at (-1, -1) to keep the view from
//    catching real taps without disabling interaction outright. (The
//    surrounding SwiftUI parent must also NOT apply `.allowsHitTesting(false)`
//    for the same reason — both flags translate to the same underlying
//    UIKit state.)
//
//  - Text-input safety: when a `UITextField` / `UITextView` becomes first
//    responder, it sits higher in the responder chain than this host. The
//    field swallows the keys it binds (Cmd-Z/X/C/V/A, plain letters while
//    typing); everything else bubbles up to us. After the field resigns,
//    `didMoveToWindow` / a brief async hop re-claims first responder.
//

import SwiftUI
import UIKit

struct KeyCommandHost: UIViewRepresentable {
    let engine: GameEngine
    let sidebarState: SidebarState?

    func makeUIView(context: Context) -> KeyCommandHostView {
        let v = KeyCommandHostView(frame: CGRect(x: -1, y: -1, width: 1, height: 1))
        v.engine = engine
        v.sidebarState = sidebarState
        return v
    }

    func updateUIView(_ uiView: KeyCommandHostView, context: Context) {
        uiView.sidebarState = sidebarState
        // Re-claim first responder when SwiftUI re-renders us (e.g. after
        // a sheet dismiss may have stolen focus). becomeFirstResponder()
        // is cheap and idempotent.
        if uiView.window != nil && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyCommandHostView, context: Context) -> CGSize? {
        CGSize(width: 1, height: 1)
    }
}

// MARK: - Hosting view

final class KeyCommandHostView: UIView {
    fileprivate weak var engine: GameEngine?
    fileprivate var sidebarState: SidebarState?

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // Defensive: explicitly OFF for the focus engine so we don't show
        // a focus halo. NOT the same as `isUserInteractionEnabled = false`
        // — focus is iPad's Pointer/Voice-Control halo, interaction is
        // touches.
        focusGroupPriority = .ignored
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Claim first responder asynchronously so the host has finished
        // mounting and SwiftUI is past the layout pass. Without the async
        // hop, `becomeFirstResponder()` sometimes silently returns false
        // when called inside the same runloop tick as `didMoveToWindow`.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            let ok = self.becomeFirstResponder()
            #if DEBUG
            debugLog("⌨️ KeyCommandHost becomeFirstResponder → \(ok); commands: \(self.keyCommands?.count ?? 0)")
            #endif
        }
    }

    // MARK: - Key commands

    /// UIKit calls this when activating the responder and again when it
    /// rebuilds the menu / Cmd-Hold HUD. Cheap enough to rebuild from the
    /// descriptor table each time.
    override var keyCommands: [UIKeyCommand]? {
        KeyboardShortcuts.all.map { descriptor in
            let command = UIKeyCommand(
                input: descriptor.input,
                modifierFlags: descriptor.modifiers,
                action: #selector(handleKeyCommand(_:))
            )
            command.discoverabilityTitle = descriptor.name
            return command
        }
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        guard let engine else { return }
        let input = command.input ?? ""
        let flags = command.modifierFlags

        // Konami sequence intercept — must run BEFORE the descriptor
        // dispatch so the side-effects (autobuyer pause on "a", BH toggle
        // on "b") still fire as the user enters the sequence. Web
        // behaviour: actions run, Konami also tracks.
        if flags.isEmpty, let symbol = KonamiTracker.symbol(forInput: input) {
            KonamiTracker.shared.record(symbol: symbol, engine: engine)
        }

        // Match case-insensitively on the literal input — UIKit normalizes
        // letter input by lowercasing for shift-modified shortcuts.
        guard let descriptor = KeyboardShortcuts.all.first(where: {
            $0.input.lowercased() == input.lowercased() && $0.modifiers == flags
        }) else { return }
        switch descriptor.action {
        case .engine(let body):
            body(engine)
        case .engineSidebar(let body):
            body(engine, sidebarState)
        }
    }
}
