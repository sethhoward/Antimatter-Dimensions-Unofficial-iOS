//
//  AutomatorDocsView.swift
//  AntiMatter
//
//  Automator documentation panel with tabbed sections:
//  - Introduction: overview of Automator features (matches AutomatorDocsIntroPage.vue)
//  - Commands: searchable command reference (matches AutomatorDocsCommandList.vue)
//

import SwiftUI

// MARK: - Docs Container

struct AutomatorDocsView: View {
    let engine: GameEngine

    @State private var selectedSection: DocsSection = .intro

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            HStack(spacing: 0) {
                docsTab("Introduction", section: .intro, icon: "book")
                docsTab("Commands", section: .commands, icon: "list.bullet.rectangle")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.1))

            // Content
            switch selectedSection {
            case .intro:
                AutomatorIntroView()
            case .commands:
                AutomatorCommandListView(engine: engine)
            }
        }
    }

    private func docsTab(_ title: String, section: DocsSection, icon: String) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(selectedSection == section ? GameColor.reality : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedSection == section ? Color.white.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private enum DocsSection {
        case intro
        case commands
    }
}

// MARK: - Introduction Page

private struct AutomatorIntroView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to the Automator!")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(GameColor.reality)

                Text("This page gives a broad overview of the Automator. Specific details can be found in the Commands tab or the How To Play entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                docSection("Scripting Language") {
                    Text("The Automator uses a custom scripting language to perform game actions for you. Use the \(Text("Commands").fontWeight(.bold)) tab to see all available commands. You can also define constants as shorthand names for values.")
                }

                docSection("Layout") {
                    Text("The Automator is split into two halves: the left side contains your script and execution controls, and the right side contains documentation, script management, and error information.")
                }

                docSection("Making Scripts") {
                    Text("Switch between scripts or create new ones in the Scripts panel. Scripts can be renamed or deleted via long-press context menus. The Automator always keeps at least one script.")
                }

                docSection("Writing Scripts") {
                    Text("Type directly into the text editor on the left side. The editor supports syntax highlighting for commands, currencies, numbers, and comparisons.")
                }

                docSection("Debugging") {
                    Text("The Errors panel shows compilation errors that prevent your script from running. Fix all errors before the Automator can execute your script.")
                }

                docSection("Importing & Exporting") {
                    Text("Scripts can be exported to and imported from the clipboard using the buttons in the Scripts panel. Exported scripts are encoded in a text format that can be shared with others.")
                }

                docSection("Script Saving") {
                    Text("Script changes are saved automatically after a short delay. There are character limits per script and across all scripts to reduce lag — these are shown above the editor.")
                }

                docSection("Automator Speed") {
                    Text("The Automator runs commands at a rate that increases with your Reality count, up to a maximum of 1,000 commands per real-time second.")
                }
            }
            .padding(12)
        }
    }

    private func docSection(_ title: String, @ViewBuilder content: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            content()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Command Reference

private struct AutomatorCommandListView: View {
    let engine: GameEngine

    @State private var commands: [AutomatorCommandDoc] = []
    @State private var expandedID: String?
    @State private var isLoaded = false

    var body: some View {
        Group {
            if !isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commands.isEmpty {
                Text("No command documentation available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        Text("Tap a command to see its syntax and description.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        ForEach(commands) { cmd in
                            commandRow(cmd)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .onAppear {
            guard !isLoaded else { return }
            engine.loadAutomatorDocs { docs in
                commands = docs.enumerated().compactMap { index, d in
                    let id: String
                    if let s = d["id"] as? String, !s.isEmpty {
                        id = s
                    } else if let n = d["id"] as? Int {
                        id = "\(n)"
                    } else {
                        id = "\(index)"
                    }
                    let keyword = d["keyword"] as? String ?? ""
                    guard !keyword.isEmpty else { return nil }
                    return AutomatorCommandDoc(
                        id: id,
                        keyword: keyword,
                        syntax: stripHTML(d["syntax"] as? String ?? ""),
                        description: stripHTML(d["desc"] as? String ?? ""),
                        category: d["category"] as? Int ?? 0
                    )
                }
                isLoaded = true
            }
        }
    }

    private func commandRow(_ cmd: AutomatorCommandDoc) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedID = expandedID == cmd.id ? nil : cmd.id
                }
            } label: {
                HStack {
                    Text(cmd.keyword)
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(GameColor.syntaxCommand)
                    Spacer()
                    Image(systemName: expandedID == cmd.id ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expandedID == cmd.id {
                if !cmd.syntax.isEmpty {
                    Text(cmd.syntax)
                        .font(.caption2.monospaced())
                        .foregroundStyle(GameColor.syntaxString)
                        .textSelection(.enabled)
                }
                if !cmd.description.isEmpty {
                    Text(cmd.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(expandedID == cmd.id ? Color.white.opacity(0.03) : .clear)
    }

    private func stripHTML(_ str: String) -> String {
        str
            // Replace <br> variants with a single space (or newline-equivalent)
            .replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
            // Strip all remaining HTML tags
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            // Decode HTML entities
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            // Collapse whitespace runs (from template literal indentation) into single spaces
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

private struct AutomatorCommandDoc: Identifiable {
    let id: String
    let keyword: String
    let syntax: String
    let description: String
    let category: Int
}
