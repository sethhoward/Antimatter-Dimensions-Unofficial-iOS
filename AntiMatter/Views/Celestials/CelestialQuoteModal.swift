//
//  CelestialQuoteModal.swift
//  AntiMatter
//
//  Ports `src/components/modals/celestial-quotes/CelestialQuoteModal.vue`
//  and its subviews (CelestialQuoteLine, CelestialQuoteBackground).
//
//  Visual structure:
//   - Full-screen dimmed overlay (c-modal-overlay).
//   - Rounded black card (30rem × 30rem in web; we scale to viewport).
//   - Huge ghostly celestial symbol behind the text (0.2 opacity, celestial color).
//   - Inner/outer colored box-shadow = glow (celestial color).
//   - Celestial name at top.
//   - Single line of quote text centered.
//   - Left/right chevron arrows on sides (hidden on first/last line respectively).
//   - Check-circle button at bottom on the final line only.
//

import SwiftUI

struct CelestialQuoteModal: View {
    let quote: QuoteState
    let engine: GameEngine

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0

    private var line: QuoteLineInfo? {
        guard !quote.lines.isEmpty else { return nil }
        return quote.lines[min(max(index, 0), quote.lines.count - 1)]
    }

    private var isFirst: Bool { index <= 0 }
    private var isLast: Bool { index >= quote.lines.count - 1 }

    /// Primary celestial color for this line (falls back to quote's celestial).
    private var celestialColor: Color {
        CelestialPalette.color(for: line?.celestialKey ?? quote.celestialKey)
    }

    private var celestialSymbol: String {
        CelestialPalette.symbol(for: line?.celestialKey ?? quote.celestialKey)
    }

    /// Optional SF Symbol name for celestials whose Unicode glyph doesn't
    /// render cleanly as a large ghost watermark (e.g. Enslaved's `⛓` renders
    /// as a color emoji). When non-nil, the modal draws an Image instead of Text.
    private var celestialSFSymbol: String? {
        CelestialPalette.sfSymbol(for: line?.celestialKey ?? quote.celestialKey)
    }

    var body: some View {
        ZStack {
            // l-modal-overlay — dim full-screen backdrop
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    // Clicking outside the card → try close (only works when on last line)
                    if isLast { close() }
                }

            card
                .padding(24)
        }
    }

    // MARK: - Card

    private var card: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // Layer 1: Giant ghost celestial symbol (c-modal-celestial-quote__symbol)
                // 25rem font size on a 30rem card → ~83% of card size.
                // Celestials whose web Font Awesome glyph doesn't map to a clean
                // iOS glyph (e.g. Enslaved's `⛓` renders as a colour emoji) use
                // an SF Symbol so the watermark stays a soft monochromatic
                // silhouette tinted by the celestial's accent color.
                if let sf = celestialSFSymbol {
                    Image(systemName: sf)
                        .font(.system(size: side * 0.6, weight: .regular))
                        .foregroundStyle(celestialColor.opacity(0.2))
                        .shadow(color: celestialColor.opacity(0.2), radius: 32)
                } else {
                    Text(celestialSymbol)
                        .font(.system(size: side * 0.75, weight: .bold))
                        .foregroundStyle(celestialColor.opacity(0.2))
                        .shadow(color: celestialColor.opacity(0.2), radius: 32)
                }

                // Layer 2: Content (celestial name + text + arrows + close)
                content(cardSize: side)
            }
            .frame(width: side, height: side)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(celestialColor, lineWidth: 2)
            )
            // Box-shadow: 0 0 1.5rem 0.1rem (outer glow) + 0 0 1rem 0.1rem inset
            .shadow(color: celestialColor.opacity(0.7), radius: 24)
            .shadow(color: celestialColor.opacity(0.5), radius: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(cardSize: CGFloat) -> some View {
        ZStack {
            // Celestial name at top
            if line?.showCelestialName ?? true {
                Text(quote.celestialDisplayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(celestialColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, cardSize * 0.05)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            // Message text — centered, padded away from arrows.
            // Monospaced design: Pelle's quotes (and a few V/Lai'tela ones)
            // use `wordShift.wordCycle()`, which keeps the cycled word at a
            // constant character count via space padding. With a variable-
            // width font that constant count still translates to a varying
            // visual width — the line reflows every 250ms and the modal
            // jitters. Monospaced glyphs make character count == visual
            // width, so the cycle animates smoothly without resizing.
            Text(line?.text ?? "")
                .font(.system(size: cardSize * 0.05, weight: .medium, design: .monospaced))
                .foregroundStyle(celestialColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, cardSize * 0.15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Left arrow
            HStack {
                arrow(name: "chevron.left.circle.fill", visible: !isFirst) {
                    index -= 1
                }
                Spacer()
                arrow(name: "chevron.right.circle.fill", visible: !isLast) {
                    index += 1
                }
            }
            .padding(.horizontal, cardSize * 0.04)

            // Close button (bottom, last line only)
            if isLast {
                VStack {
                    Spacer()
                    Button {
                        close()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: cardSize * 0.08))
                            .foregroundStyle(celestialColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, cardSize * 0.05)
                }
            }

            // Line counter (bottom-left, small)
            VStack {
                Spacer()
                HStack {
                    Text("\(index + 1)/\(quote.lines.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(celestialColor.opacity(0.6))
                        .padding(.leading, cardSize * 0.05)
                        .padding(.bottom, cardSize * 0.05)
                    Spacer()
                    if quote.queueSize > 0 {
                        Text("+\(quote.queueSize) queued")
                            .font(.caption2)
                            .foregroundStyle(celestialColor.opacity(0.6))
                            .padding(.trailing, cardSize * 0.05)
                            .padding(.bottom, cardSize * 0.05)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func arrow(name: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 36))
                .foregroundStyle(celestialColor)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
    }

    // MARK: - Actions

    private func close() {
        index = 0
        engine.advanceQuoteQueue()
        dismiss()
    }
}

// MARK: - Celestial color palette

enum CelestialPalette {
    static func color(for key: String) -> Color {
        switch key {
        case "teresa":   GameColor.teresa
        case "effarig":  GameColor.effarig
        case "enslaved": GameColor.enslaved
        case "v":        GameColor.v
        case "ra":       GameColor.ra
        case "laitela":  GameColor.laitela
        case "pelle":    GameColor.pelle
        default:         GameColor.celestials
        }
    }

    static func displayName(for key: String) -> String {
        switch key {
        case "teresa":   "Teresa"
        case "effarig":  "Effarig"
        case "enslaved": "The Nameless Ones"
        case "v":        "V"
        case "ra":       "Ra"
        case "laitela":  "Lai'tela"
        case "pelle":    "Pelle"
        default:         "Celestial"
        }
    }

    static func symbol(for key: String) -> String {
        switch key {
        case "teresa":   "Ϟ"
        case "effarig":  "Ϙ"
        case "enslaved": "⛓"
        case "v":        "⌬"
        case "ra":       "☀"
        case "laitela":  "ᛝ"
        case "pelle":    "♅"
        default:         "✨"
        }
    }

    /// Optional SF Symbol fallback for celestials whose web Font Awesome glyph
    /// (`\uf0c1` chain for Enslaved, etc.) doesn't render on iOS without the
    /// font bundled. Non-nil cases render an Image instead of Text.
    static func sfSymbol(for key: String) -> String? {
        switch key {
        case "enslaved": "link"
        // Ra's Unicode sun (☀, U+2600) renders as Apple Color Emoji by default,
        // which doesn't fit the monochrome celestial watermark look. Route to
        // the plain SF Symbol sun instead.
        case "ra":       "sun.max.fill"
        default:         nil
        }
    }
}

// MARK: - Quote History sheet

struct CelestialQuoteHistoryView: View {
    let celestialKey: String
    let engine: GameEngine

    @Environment(\.dismiss) private var dismiss

    private var accent: Color { CelestialPalette.color(for: celestialKey) }

    var body: some View {
        NavigationStack {
            List(engine.celestialQuoteHistory) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.firstLine)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if entry.totalLines > 1 {
                        Text("\(entry.totalLines) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    engine.replayQuote(celestialKey: celestialKey, quoteId: entry.quoteId)
                    dismiss()
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(accent.opacity(0.1))
            .adaptiveSheetTitle("\(CelestialPalette.displayName(for: celestialKey)) — History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: celestialKey) {
            engine.loadQuoteHistory(for: celestialKey)
        }
        .presentationDetents([.medium, .large])
    }
}
