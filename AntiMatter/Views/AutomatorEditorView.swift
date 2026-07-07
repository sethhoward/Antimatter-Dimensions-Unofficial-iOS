//
//  AutomatorEditorView.swift
//  AntiMatter
//
//  Top-level Automator editor layout. iPad: split pane (editor + panel).
//  iPhone: segmented tabs (Editor / Scripts / Errors).
//  Matches AutomatorTab.vue layout.
//

import SwiftUI

struct AutomatorEditorView: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    @State private var scriptText = ""
    @AppStorage("automatorSelectedPanel") private var selectedPanelRaw: String = AutomatorPanel.docs.rawValue
    @State private var hasLoadedInitialScript = false
    @State private var isPanelCollapsed = false

    private var selectedPanel: AutomatorPanel {
        get { AutomatorPanel(rawValue: selectedPanelRaw) ?? .docs }
        nonmutating set { selectedPanelRaw = newValue.rawValue }
    }

    private var state: AutomatorEditorState { engine.gameState.automatorEditorState }

    var body: some View {
        // Hard-clamp the whole editor subtree to the available width. Inside
        // SubtabPager's UIHostingController, `.frame(maxWidth: .infinity)` only
        // *allows* growth — a child that won't compress below the screen width
        // (the controls bar + a greedy panel) makes the subtree wider than the
        // page, and SwiftUI then centers it, bleeding off both edges (the
        // iPhone 13 mini overflow). GeometryReader gives us the concrete page
        // width; framing to it forces every child to fit (Spacers collapse,
        // the panel pill row scrolls) instead of overflowing.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Controls bar
                AutomatorControlsBar(engine: engine)

                Divider().background(Color.white.opacity(0.1))

                if metrics.isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .onAppear {
            loadScriptIfNeeded()
        }
        .onChange(of: state.editingScriptID) { _, _ in
            loadScriptIfNeeded()
        }
    }

    // MARK: - iPad Layout (split pane)

    private var regularLayout: some View {
        GeometryReader { geo in
            let panelWidth = isPanelCollapsed ? 0.0 : min(geo.size.width * 0.4, 400.0)
            let editorWidth = geo.size.width - panelWidth
            HStack(spacing: 0) {
                // Left: editor
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        charCountBar
                        panelCollapseButton
                    }
                    editorView
                }
                .frame(width: editorWidth)

                if !isPanelCollapsed {
                    Divider().background(Color.white.opacity(0.1))

                    // Right: panel
                    VStack(spacing: 0) {
                        panelPicker
                        panelContent
                    }
                    .frame(width: panelWidth, alignment: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPanelCollapsed)
        }
    }

    private var panelCollapseButton: some View {
        Button {
            isPanelCollapsed.toggle()
        } label: {
            Image(systemName: isPanelCollapsed ? "sidebar.trailing" : "sidebar.trailing")
                .font(.caption)
                .foregroundStyle(isPanelCollapsed ? GameColor.reality : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .background(Color(white: 0.08))
    }

    // MARK: - iPhone Layout (tabbed)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            compactPanelPicker
            compactPanelContent
        }
        .frame(maxWidth: .infinity)
    }

    // Scrollable pill row instead of a segmented Picker: 5 panels won't fit a
    // segmented control on a 375pt screen, and a segmented Picker's intrinsic
    // width was forcing horizontal overflow inside SubtabPager's UIHostingController.
    // A horizontal ScrollView of Button-based pills has no minimum intrinsic width,
    // so it clamps to the page width. (Buttons also fire reliably in SubtabPager,
    // unlike segmented/menu pickers — see the design notes "SubtabPager Known Issues".)
    private var compactPanelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                panelTab("Editor", panel: .editor, icon: "chevron.left.forwardslash.chevron.right")
                panelTab("Scripts", panel: .scripts, icon: "doc.text")
                panelTab("Errors", panel: .errors, icon: "exclamationmark.triangle", badge: state.errors.count)
                panelTab("Docs", panel: .docs, icon: "book")
                panelTab("Constants", panel: .constants, icon: "function")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var compactPanelContent: some View {
        switch selectedPanel {
        case .editor:
            VStack(spacing: 0) {
                charCountBar
                editorView
            }
        case .scripts:
            AutomatorScriptListView(engine: engine) { _ in
                loadScriptIfNeeded()
                selectedPanel = .editor
            }
        case .errors:
            AutomatorErrorListView(errors: state.errors) { line in
                selectedPanel = .editor
                // scrollToLine handled by followExecution or next frame
            }
        case .docs:
            AutomatorDocsView(engine: engine)
        case .constants:
            AutomatorConstantsView(engine: engine)
        }
    }

    // MARK: - Panel Picker (iPad right side)

    private var panelPicker: some View {
        HStack(spacing: 0) {
            panelTab("Scripts", panel: .scripts, icon: "doc.text")
            panelTab("Errors", panel: .errors, icon: "exclamationmark.triangle", badge: state.errors.count)
            panelTab("Docs", panel: .docs, icon: "book")
            panelTab("Constants", panel: .constants, icon: "function")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func panelTab(_ title: String, panel: AutomatorPanel, icon: String, badge: Int = 0) -> some View {
        Button {
            selectedPanel = panel
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption2.weight(.medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(GameColor.badPink))
                }
            }
            .foregroundStyle(selectedPanel == panel ? GameColor.reality : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedPanel == panel ? Color.white.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .editor:
            // On iPad, editor is always visible on the left, so redirect to scripts
            AutomatorScriptListView(engine: engine) { _ in
                loadScriptIfNeeded()
            }
        case .scripts:
            AutomatorScriptListView(engine: engine) { _ in
                loadScriptIfNeeded()
            }
        case .errors:
            AutomatorErrorListView(errors: state.errors) { line in
                // Line tap — could trigger scroll via a published property later
            }
        case .docs:
            AutomatorDocsView(engine: engine)
        case .constants:
            AutomatorConstantsView(engine: engine)
        }
    }

    // MARK: - Shared Components

    private var charCountBar: some View {
        HStack {
            if let script = state.scripts.first(where: { $0.id == state.editingScriptID }) {
                Text(script.name.isEmpty ? "Untitled" : script.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameColor.reality)
            }
            Spacer()
            Text("\(state.currentScriptChars)/\(state.maxScriptChars)")
                .font(.caption2)
                .foregroundStyle(
                    state.currentScriptChars > state.maxScriptChars ? GameColor.badPink : .secondary
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color(white: 0.08))
    }

    private var editorView: some View {
        AutomatorTextEditorView(
            text: $scriptText,
            activeLine: state.isOn ? state.currentLine : -1,
            errorLines: Set(state.errors.map(\.startLine)),
            followExecution: state.followExecution
        ) { newText in
            engine.automatorSaveScript(state.editingScriptID, content: newText)
        }
    }

    // MARK: - Script Loading

    private func loadScriptIfNeeded() {
        let id = state.editingScriptID
        guard id > 0 else { return }
        engine.loadAutomatorScriptContent(id) { content in
            scriptText = content
            hasLoadedInitialScript = true
        }
    }
}

// MARK: - Panel Enum

enum AutomatorPanel: String, Hashable {
    case editor
    case scripts
    case errors
    case docs
    case constants
}
