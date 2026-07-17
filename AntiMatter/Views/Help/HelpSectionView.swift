//
//  HelpSectionView.swift
//  AntiMatter
//
//  Renders one help section: loads its markdown from
//  `Resources/HelpContent/<filename>.md`, walks the resulting blocks, and
//  draws each as a `Text(AttributedString)` paragraph, bullet row, or
//  heading.
//
//  Loading happens once in `.task` so we don't re-parse on every redraw.
//

import SwiftUI

struct HelpSectionView: View {
    let section: HelpSection
    let engine: GameEngine

    @State private var blocks: [HelpBlock] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    switch block.kind {
                    case .heading:
                        Text(block.content)
                            .font(.title3.weight(.semibold))
                            .padding(.top, 6)
                    case .paragraph:
                        Text(block.content)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    case .bullet:
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text(block.content)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .adaptiveSheetTitle(section.title)
        .task {
            let flags = section.progressionFlags(engine)
            blocks = MarkdownLoader.load(filename: section.filename, activeFlags: flags)
        }
    }
}
