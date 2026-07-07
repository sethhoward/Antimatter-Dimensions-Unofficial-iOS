//
//  HelpIndexView.swift
//  AntiMatter
//
//  Top level of the Help subtab (Options → Help). Lists the sections
//  currently visible for the player's progression, wrapped in a
//  `NavigationStack` so each row can push to `HelpSectionView`.
//
//  Filter UX uses an inline `TextField` rather than `.searchable` — the
//  built-in modifier wants a nav bar to anchor itself and is finicky inside
//  the iPhone SubtabPager's `UIHostingController` boundary. Inline is
//  reliable on both platforms.
//
//  Bodies are loaded lazily on first appear (~4 small files in Phase 1,
//  ~45 small files in Phase 2; total bundle weight well under 100 KB).
//

import SwiftUI

struct HelpIndexView: View {
    let engine: GameEngine

    @State private var searchText: String = ""
    @State private var bodies: [String: String] = [:]
    @FocusState private var searchFocused: Bool

    private var visibleSections: [HelpSection] {
        HelpContent.visibleSections(for: engine)
    }

    private var filteredSections: [HelpSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return visibleSections }
        return visibleSections.filter { section in
            if section.title.lowercased().contains(query) { return true }
            if let body = bodies[section.id], body.lowercased().contains(query) { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                List {
                    ForEach(filteredSections) { section in
                        NavigationLink {
                            HelpSectionView(section: section, engine: engine)
                        } label: {
                            Text(section.title)
                                .font(.body)
                        }
                    }

                    if filteredSections.isEmpty && !searchText.isEmpty {
                        Text("No help sections match \"\(searchText)\".")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
            .task {
                loadBodiesIfNeeded()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search help", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func loadBodiesIfNeeded() {
        guard bodies.isEmpty else { return }
        var loaded: [String: String] = [:]
        for section in HelpContent.sections {
            let flags = section.progressionFlags(engine)
            loaded[section.id] = MarkdownLoader.plainText(filename: section.filename, activeFlags: flags)
        }
        bodies = loaded
    }
}
