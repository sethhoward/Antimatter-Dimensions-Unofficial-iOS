//
//  GameButton.swift
//  AntiMatter
//
//  Standard game button style matching the web Modern UI.
//  Supports ButtonTheme for per-context enabled/disabled styling.
//  Tap highlight uses the web's hover color for tactile feedback.
//

import SwiftUI

/// Standard game button: dark bg, colored border, rounded rect.
/// On press, background fills with the web hover color for tactile feedback.
///
/// Two initializers:
/// 1. `GameButton(theme:isEnabled:action:label:)` — full theme control
/// 2. `GameButton(borderColor:isEnabled:action:label:)` — convenience; uses `.standard` theme with custom border
struct GameButton<Label: View>: View {
    let theme: ButtonTheme
    var isEnabled: Bool = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    /// Theme-based initializer — derives all colors from the theme.
    init(theme: ButtonTheme, isEnabled: Bool = true, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.theme = theme
        self.isEnabled = isEnabled
        self.action = action
        self.label = label
    }

    /// Convenience initializer — standard theme with a custom enabled border color.
    init(borderColor: Color, isEnabled: Bool = true, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        var t = ButtonTheme.standard
        t = ButtonTheme(
            enabledBorder: borderColor,
            enabledBackground: t.enabledBackground,
            enabledText: t.enabledText,
            pressedBackground: t.pressedBackground,
            pressedText: t.pressedText,
            disabledBorder: t.disabledBorder,
            disabledBackground: t.disabledBackground,
            disabledText: t.disabledText
        )
        self.theme = t
        self.isEnabled = isEnabled
        self.action = action
        self.label = label
    }

    private var currentBorder: Color { isEnabled ? theme.enabledBorder : theme.disabledBorder }

    var body: some View {
        Button(action: {
            // Any GameButton tap is a user interaction — reset the idle
            // throttle clock (no-op when the engine hook isn't registered).
            InteractionTracker.shared.recordTouch()
            Haptics.tap()
            action()
        }) {
            label()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(GameButtonStyle(theme: theme, isEnabled: isEnabled))
        .allowsHitTesting(isEnabled)
        .roundedBorder(currentBorder)
    }
}

/// Shared hook called by input surfaces (GameButton, sidebar/tab bar
/// selections, dimension rows, etc.) to notify the engine of a user
/// interaction. The engine registers itself on `start()`; unregistered
/// state is a safe no-op. Decouples SwiftUI leaf views from GameEngine.
final class InteractionTracker {
    static let shared = InteractionTracker()
    private init() {}
    var recordTouch: () -> Void = {}
}

// MARK: - Custom ButtonStyle with press highlight

/// Applies the theme's background/text colors and swaps to the pressed (hover) colors on tap.
private struct GameButtonStyle: ButtonStyle {
    let theme: ButtonTheme
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .foregroundStyle(pressed ? theme.pressedText : (isEnabled ? theme.enabledText : theme.disabledText))
            .background(
                (pressed ? theme.pressedBackground : (isEnabled ? theme.enabledBackground : theme.disabledBackground)),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}
