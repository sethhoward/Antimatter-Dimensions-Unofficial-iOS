//
//  KonamiTracker.swift
//  AntiMatter
//
//  Hardware-keyboard sequence tracker for SecretAchievement(17) "30 Lives".
//  Mirrors web `src/core/hotkeys.js` `testKonami(character)` (lines 552-568):
//
//      const konamiCode = [
//          "up", "up", "down", "down",
//          "left", "right", "left", "right",
//          "b", "a", "enter"
//      ];
//      // On full match: SecretAchievement(17).unlock();
//      //                Currency.antimatter.bumpTo(30);
//      //                Speedrun.startTimer();
//
//  iOS plumbing:
//    - `KeyCommandHost.handleKeyCommand` calls `KonamiTracker.shared.record(...)`
//      BEFORE dispatching the descriptor's action. Every keystroke that
//      UIKit fires for a registered `UIKeyCommand` flows through us; the
//      existing autobuyer/BH bindings on "a"/"b" still run their own
//      actions (the Konami code shares those keys — same behaviour on web,
//      where pressing the sequence visibly pauses autobuyers / toggles BH
//      as a side effect).
//    - To make arrows + Enter reach the host, KeyboardShortcuts.swift
//      registers them with no-op actions (descriptor existence is what
//      tells UIKit to route the keystroke to us).
//
//  Match window:
//    - Web has no time limit between steps; once you start the sequence
//      you can pause indefinitely. We mirror that — no timeout.
//    - Web's reset-on-mistake logic is the funky "if you double up at
//      position 2, stay at 2" rule for the duplicated "up" inputs. We
//      replicate it verbatim.
//

import Foundation
import UIKit

final class KonamiTracker {
    static let shared = KonamiTracker()
    private init() {}

    /// Symbolic names, matching web's `konamiCode` exactly.
    private let sequence: [String] = [
        "up", "up", "down", "down",
        "left", "right", "left", "right",
        "b", "a", "enter"
    ]

    private var step = 0

    /// Normalize a UIKeyCommand's `input` value into one of the symbols
    /// the sequence uses. Returns `nil` if the keystroke isn't relevant
    /// (we still pass through, but skip the sequence check).
    static func symbol(forInput input: String) -> String? {
        switch input {
        case UIKeyCommand.inputUpArrow:    return "up"
        case UIKeyCommand.inputDownArrow:  return "down"
        case UIKeyCommand.inputLeftArrow:  return "left"
        case UIKeyCommand.inputRightArrow: return "right"
        // Carriage return is the Enter key on macOS/iPadOS hardware keyboards.
        case "\r", "\n":                   return "enter"
        default:
            let lower = input.lowercased()
            if lower == "a" || lower == "b" { return lower }
            return nil
        }
    }

    /// Feed one keystroke. Fires SecretAchievement(17) + the +30 antimatter
    /// bump + speedrun start when the full sequence completes.
    func record(symbol: String, engine: GameEngine) {
        // Mirrors web `testKonami` lines 560-563 verbatim.
        if sequence[step] == symbol {
            step += 1
        } else if step == 2 && symbol == "up" {
            // Lingering on consecutive "up" past position 2 doesn't reset.
            step = 2
        } else if symbol == sequence[0] {
            step = 1
        } else {
            step = 0
        }

        if sequence.count <= step {
            step = 0  // Reset for any future taps (we don't gate on isUnlocked).
            engine.unlockKonamiAchievement()
        }
    }
}
