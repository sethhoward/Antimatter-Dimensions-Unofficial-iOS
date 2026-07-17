//
//  GameEngine+Keyboard.swift
//  AntiMatter
//
//  Action wrappers used by the hardware-keyboard support (KeyCommandHost),
//  plus visibility predicate evaluation for the Keyboard Shortcuts sheet.
//
//  All bindings are *registered* unconditionally — these helpers are only
//  consulted at sheet-open time to decide which rows to show.
//

import Foundation
import JavaScriptCore

extension GameEngine {

    // MARK: - Action wrappers (missing siblings to existing engine methods)

    /// Toggle Time Study respec (`shift+e`). Matches web `hotkeys.js:108-111`.
    func toggleTSRespec() {
        jsAsync("""
            player.respec = !player.respec;
            if (typeof GameUI !== "undefined" && GameUI.notify && GameUI.notify.info) {
                GameUI.notify.info("Time Study respec is now " + (player.respec ? "active" : "inactive"));
            }
        """)
    }

    /// Toggle the Automator between RUNNING and PAUSED (`u`). Web's
    /// `keyboardAutomatorToggle()`. Different from `automatorPlay` (which only
    /// starts) — this flips state. Mirrors AutomatorControls.vue's play button.
    func automatorToggleRunning() {
        jsAsync("""
            (function(){
                if (typeof AutomatorBackend === "undefined") return;
                if (AutomatorBackend.isRunning) AutomatorBackend.mode = 1; // PAUSE
                else if (AutomatorBackend.isOn) AutomatorBackend.mode = 0; // RUN (was paused)
                else AutomatorBackend.start(player.reality.automator.state.editorScript);
            })()
        """)
    }

    /// Restart Automator (`shift+u`). Web's `keyboardAutomatorRestart()`.
    /// Already available as `automatorRewind()`; kept here as a semantically
    /// named alias used by the binding table.
    func automatorRestart() { automatorRewind() }

    /// Armageddon (`z`, Pelle-doomed). Web's `armageddonRequest()`. JS-side
    /// gates on `Pelle.isDoomed` and shows the confirmation modal itself.
    func armageddonRequest() {
        jsAsync("(function(){ if (typeof armageddonRequest === \"function\") armageddonRequest(); })()")
    }

    /// Toggle Pelle glyph respec (`shift+z`). Web `hotkeys.js:177-185`.
    /// Distinct from `toggleGlyphRespec` (`shift+y`) — same backing field but
    /// gated on `Pelle.isDoomed`.
    func togglePelleGlyphRespec() {
        jsAsync("""
            (function(){
                if (!Pelle.isDoomed) return;
                player.reality.respec = !player.reality.respec;
                if (typeof GameUI !== "undefined" && GameUI.notify && GameUI.notify.info) {
                    GameUI.notify.info("Glyph respec is now " + (player.reality.respec ? "active" : "inactive"));
                }
            })()
        """)
    }

    /// Toggle Lai'tela Continuum (`alt+a`). Web's `keyboardToggleContinuum()`.
    /// Gated on `Laitela.continuumUnlocked` JS-side.
    func toggleContinuum() {
        jsAsync("""
            (function(){
                if (typeof Laitela === "undefined" || !Laitela.continuumUnlocked) return;
                if (typeof Laitela.setContinuum === "function") {
                    Laitela.setContinuum(!!player.auto.disableContinuum);
                } else {
                    player.auto.disableContinuum = !player.auto.disableContinuum;
                }
            })()
        """)
    }

    /// Buy max Time Theorems (covers no specific hotkey, kept for future use).

    // MARK: - Sheet dismissal (Esc / Cmd-.)

    /// Dismiss the topmost game-managed sheet. Priority: prestige modal →
    /// active celestial quote → iCloud conflict sheet → iCloud first-enable
    /// sheet. Returns true if something was dismissed. View-local sheets
    /// (Backup list, Glyph presets, etc.) handle their own dismiss; the user
    /// can swipe them down.
    @discardableResult
    @MainActor
    func dismissTopGameSheet() -> Bool {
        if pendingModal != nil {
            pendingModal = nil
            return true
        }
        if activeQuote != nil {
            activeQuote = nil
            return true
        }
        if let svc = cloudSaveService {
            if svc.pendingConflict != nil {
                svc.dismissConflict()
                return true
            }
            if svc.pendingFirstEnable != nil {
                svc.pendingFirstEnable = nil
                return true
            }
        }
        return false
    }

    // MARK: - Visibility predicate batch eval

    /// Returns a snapshot of every visibility predicate referenced by the
    /// shortcuts table. Sheet renders shortcut rows iff the matching key is
    /// `true`. Called on-demand when the sheet appears — never per-tick.
    @MainActor
    func loadKeyboardShortcutVisibility(completion: @escaping ([String: Bool]) -> Void) {
        jsQueue.async { [self] in
            let json = context.evaluateScript("""
                (function(){
                    try {
                        var canEternity = !!(typeof Player !== "undefined" && Player.canEternity);
                        var eternityUnlocked = !!(typeof PlayerProgress !== "undefined" && PlayerProgress.eternityUnlocked());
                        var dilationUnlocked = !!(typeof PlayerProgress !== "undefined" && PlayerProgress.dilationUnlocked());
                        var realityUnlocked = !!(typeof PlayerProgress !== "undefined" && PlayerProgress.realityUnlocked());
                        var infinityUnlocked = !!(typeof PlayerProgress !== "undefined" && PlayerProgress.infinityUnlocked());
                        var replicantiUnlocked = !!(typeof Replicanti !== "undefined" && Replicanti.areUnlocked);
                        var automatorUnlocked = !!(typeof Player !== "undefined" && Player.automatorUnlocked);
                        var pelleDoomed = !!(typeof Pelle !== "undefined" && Pelle.isDoomed);
                        var laitelaContinuumUnlocked = !!(typeof Laitela !== "undefined" && Laitela.continuumUnlocked);
                        var canReality = !!(typeof isRealityAvailable === "function" && isRealityAvailable());
                        var canCrunch = !!(typeof Player !== "undefined" && Player.canCrunch);
                        var tickspeedUnlocked = !!(typeof Tickspeed !== "undefined" && Tickspeed.isUnlocked);
                        var sacrificeUnlocked = !!(typeof Sacrifice !== "undefined" && Sacrifice.isVisible);
                        var dimBoostUnlocked = !!(
                            (typeof AntimatterDimension === "function" && AntimatterDimension(4).isUnlocked) ||
                            (typeof DimBoost !== "undefined" && DimBoost.purchasedBoosts > 0)
                        );
                        var galaxyUnlocked = !!(
                            (typeof AntimatterDimension === "function" && AntimatterDimension(8).isUnlocked) ||
                            (typeof player !== "undefined" && player.galaxies > 0)
                        );
                        var autobuyersUnlocked = !!(
                            typeof Autobuyers !== "undefined" &&
                            Autobuyers.unlocked &&
                            Autobuyers.unlocked.length > 0
                        );
                        var blackHolesUnlocked = !!(typeof BlackHoles !== "undefined" && BlackHoles.areUnlocked);
                        return JSON.stringify({
                            canEternity: canEternity,
                            eternityUnlocked: eternityUnlocked,
                            dilationUnlocked: dilationUnlocked,
                            realityUnlocked: realityUnlocked,
                            infinityUnlocked: infinityUnlocked,
                            replicantiUnlocked: replicantiUnlocked,
                            automatorUnlocked: automatorUnlocked,
                            pelleDoomed: pelleDoomed,
                            laitelaContinuumUnlocked: laitelaContinuumUnlocked,
                            canReality: canReality,
                            canCrunch: canCrunch,
                            tickspeedUnlocked: tickspeedUnlocked,
                            sacrificeUnlocked: sacrificeUnlocked,
                            dimBoostUnlocked: dimBoostUnlocked,
                            galaxyUnlocked: galaxyUnlocked,
                            autobuyersUnlocked: autobuyersUnlocked,
                            blackHolesUnlocked: blackHolesUnlocked
                        });
                    } catch (e) {
                        return "{}";
                    }
                })()
            """)?.toString() ?? "{}"
            let dict: [String: Bool] = {
                guard let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
                var out: [String: Bool] = [:]
                for (k, v) in obj { out[k] = (v as? Bool) ?? false }
                return out
            }()
            DispatchQueue.main.async { completion(dict) }
        }
    }
}
