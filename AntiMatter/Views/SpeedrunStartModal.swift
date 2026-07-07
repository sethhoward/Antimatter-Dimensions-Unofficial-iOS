//
//  SpeedrunStartModal.swift
//  AntiMatter
//
//  Two-page modal for starting Speedrun Mode (or, optionally, a fresh
//  non-speedrun save). Mirrors web `SpeedrunModeModal.vue`:
//    Page 1 — info / overview.
//    Page 2 — name input + "Gotta Go Fast!" type-to-confirm.
//
//  Shared by:
//    - Options → "Start Speedrun Save" entry (pre-selects speedrun, hides
//      the mode radio).
//    - Credits → "New Game" button (shows the radio so the player can pick
//      Speedrun vs Fresh Save without leaving the locked credits overlay).
//
//  HARD RESETS the save on confirm. The destructive lifecycle (timers,
//  refs, helpers) is handled by `engine.startSpeedrun` / `engine.hardReset`.
//

import SwiftUI

/// Which destructive path the modal is configured for.
enum SpeedrunStartMode: Equatable {
    /// Pre-selects Speedrun, hides the radio. Used by the Options entry.
    case speedrunOnly
    /// Shows the Speedrun / Fresh Save radio. Used by the credits "New
    /// Game" button — defaults to Speedrun, but the player can flip to a
    /// vanilla hard reset.
    case offerBoth
}

/// Selected destructive action.
private enum SpeedrunStartChoice: Hashable {
    case speedrun
    case freshSave
}

struct SpeedrunStartModal: View {
    let engine: GameEngine
    let mode: SpeedrunStartMode
    /// Called after the destructive action completes (toast already shown).
    /// The sheet dismisses itself; this is just the callback hook.
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.sidebarState) private var sidebarState

    @State private var onInfoPage = true
    @State private var name: String = ""
    @State private var confirmPhrase: String = ""
    @State private var choice: SpeedrunStartChoice = .speedrun
    @State private var inFlight = false

    private static let requiredPhrase = "Gotta Go Fast!"
    private static let requiredPhraseHardReset = "Shrek is love, Shrek is life"

    private var requiresPhrase: String {
        choice == .speedrun ? Self.requiredPhrase : Self.requiredPhraseHardReset
    }
    private var willConfirm: Bool {
        confirmPhrase == requiresPhrase
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if onInfoPage {
                    infoPage
                } else {
                    confirmPage
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if onInfoPage {
                        Button("Continue") { onInfoPage = false }
                    } else {
                        Button(choice == .speedrun ? "Start Run" : "Hard Reset",
                               role: .destructive) {
                            confirmStart()
                        }
                        .disabled(!willConfirm || inFlight)
                    }
                }
            }
            .adaptiveSheetTitle(onInfoPage ? "Entering Speedrun Mode"
                                            : "Confirm new save")
        }
    }

    // MARK: Info page

    @ViewBuilder
    private var infoPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This will start a save with additional statistics tracking for when you reach certain points of the game. These will be visible at the top of the sidebar and on a dedicated Speedrun section of Statistics.")
            Text("Almost all animations and confirmations are disabled by default. When you begin the run, the game remains paused until your antimatter changes, allowing you to configure all your settings before starting. A few achievements are given for free to mitigate weird early-game strategies.")
            Text("There is no additional content in Speedrun Mode.")
                .italic()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Confirm page

    @ViewBuilder
    private var confirmPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if mode == .offerBoth {
                modeChoiceSection
                Divider()
            }

            if choice == .speedrun {
                Text("Name your speedrun save. This has no gameplay effect — it just identifies this particular save as yours. If left blank, a random name will be generated.")
                    .font(.subheadline)
                TextField("Speedrun name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(inFlight)

                Text("Starting a speedrun will reset your save to the beginning of the game. Some things are kept — full-game completion stats, automator scripts, and Glyph cosmetics — but otherwise it's as if you had just finished the game and chose to restart.")
                    .font(.footnote)
                    .foregroundStyle(GameColor.badPink.readableOnDark())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("This will erase your save and start over from the beginning. No speedrun-mode features will be active — confirmations, animations, and glyph RNG behave normally.")
                    .font(.footnote)
                    .foregroundStyle(GameColor.badPink.readableOnDark())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Type \"\(requiresPhrase)\" below to confirm.")
                .font(.subheadline.weight(.semibold))
            TextField(requiresPhrase, text: $confirmPhrase)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .disabled(inFlight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var modeChoiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What kind of fresh start?")
                .font(.subheadline.weight(.semibold))
            modeRow(.speedrun,
                    title: "Speedrun Mode",
                    subtitle: "Fixed glyph seed, stripped confirmations, free achievements, milestone tracking.")
            modeRow(.freshSave,
                    title: "Fresh Save",
                    subtitle: "A normal new game. No speedrun features.")
        }
        .onChange(of: choice) { _, _ in
            // Reset the confirmation phrase — each path requires a
            // different gauntlet, so a phrase typed for one mode must
            // not satisfy the other.
            confirmPhrase = ""
        }
    }

    @ViewBuilder
    private func modeRow(_ value: SpeedrunStartChoice, title: String, subtitle: String) -> some View {
        Button {
            choice = value
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: choice == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(choice == value ? GameColor.eternity : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(choice == value ? GameColor.eternity : Color.white.opacity(0.15),
                            lineWidth: choice == value ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Confirm action

    private func confirmStart() {
        guard !inFlight, willConfirm else { return }
        // Fall back to a fresh `SidebarState()` if the environment value
        // wasn't injected (defensive — every parent that presents this
        // modal lives inside ContentView's sidebarState injection).
        let nav = sidebarState ?? SidebarState()
        inFlight = true
        switch choice {
        case .speedrun:
            let normalized = engine.generateSpeedrunName(name)
            engine.startSpeedrun(name: normalized, sidebarState: nav) { _ in
                onCompleted?()
                dismiss()
            }
        case .freshSave:
            // Standard hard reset — no speedrun flag, no carryover.
            engine.hardReset(sidebarState: nav)
            // hardReset toasts + navigates internally; just close.
            onCompleted?()
            dismiss()
        }
    }
}
