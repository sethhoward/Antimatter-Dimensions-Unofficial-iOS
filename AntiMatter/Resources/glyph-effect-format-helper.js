// glyph-effect-format-helper.js
//
// Single source of truth for "render a glyph's effects" formatting.
//
// Two surfaces consume this helper:
//   1. `pollGlyphs()` (Glyphs tab, equipped + inventory + active effects)
//   2. `requestReality()` (Reality confirmation modal — `GlyphSelection.upcomingGlyphs`)
//
// Both surfaces need: filter bitmask-overlapping effects by isGenerated; format
// the per-effect value via `formatSingleEffect`; detect EMPOWER/BOOST/ADDITION
// alteration and emit ▲ prefix + boost/addition color; compute the secondary
// `{value2}` via `conversion + formatSecondaryEffect`; preserve `[...]` markers
// for the Swift `glyphEffectStyledText` renderer; collapse whitespace.
//
// Returns four parallel arrays — one entry per visible effect — that callers
// spread into their per-glyph result record:
//
//   { effs:             string[]  full singleDesc, `{value}` / `{value2}` substituted, `§…§` marked
//     shortEffs:        string[]  same shape using shortDesc (fallback to singleDesc)
//     effBoostColors:   string[]  hex color for active EMPOWER/BOOST (else "")
//     effAdditionColors: string[] hex color for active ADDITION (else "")
//   }
//
// Note: this helper has no state, no event listeners — it's a pure function.
// It's still re-injected at every save-lifecycle entry point alongside the
// other helpers for consistency (and so a hypothetical future globalThis reset
// can't leave the function undefined for one of the two callers).

(function() {
    // `effLvl` (optional) overrides the level passed to
    // `getGlyphEffectValuesFromBitmask`. `pollGlyphs()` uses this for the
    // active/inventory contexts where `getAdjustedGlyphLevel(g)` returns a
    // level scaled by perks / Ra unlocks. When omitted (e.g. Reality modal's
    // upcoming glyphs, which aren't equipped or stored yet), falls back to
    // the glyph's own `level`.
    globalThis._formatGlyphEffectBlock = function(g, effLvl) {
        var effs = [];
        var shortEffs = [];
        var effBoostColors = [];
        var effAdditionColors = [];
        try {
            var level = (effLvl !== undefined && effLvl !== null) ? effLvl : g.level;
            // `getGlyphEffectValuesFromBitmask` returns ALL effects whose bitmask
            // bit is set, including bitmask-index collisions across glyph types
            // (e.g. `cursedgalaxies` shares bitmaskIndex 0 with `timepow`).
            // Filter by `isGenerated` matching whether the glyph's type itself
            // is generated. Mirrors `GlyphTooltip.vue`'s `sortedEffects`.
            var typeIsGenerated = (typeof generatedTypes !== 'undefined')
                && generatedTypes.indexOf(g.type) !== -1;

            // ALTERATION_TYPE may not be on globalThis depending on bundle
            // shape. Provide a fallback that matches the JS source values.
            var ALT = (typeof ALTERATION_TYPE !== 'undefined')
                ? ALTERATION_TYPE
                : { EMPOWER: 0, BOOST: 1, ADDITION: 2 };

            var effArr = getGlyphEffectValuesFromBitmask(g.effects, level, g.strength, g.type);
            for (var ei = 0; ei < effArr.length; ei++) {
                var eff = effArr[ei];
                // Read from the live `GlyphEffectConfig` instance, not the raw
                // setup object — the constructor defaults `formatSingleEffect`
                // to `formatEffect` (glyph-effects.js:64) and exposes the
                // `singleDesc` / `shortDesc` getters which auto-resolve
                // function-valued descriptions.
                var def = (typeof GlyphEffects !== 'undefined') ? GlyphEffects[eff.id] : null;
                if (!def) def = GameDatabase.reality.glyphEffects[eff.id];
                if (!def) continue;
                if (def.isGenerated !== typeIsGenerated) continue;

                // Alteration detection. Each effect has at most one alterationType.
                // boostColor is non-empty only for EMPOWER/BOOST when active;
                // additionColor is non-empty only for ADDITION when active.
                var boostColor = '';
                var additionColor = '';
                try {
                    var altType = def.alterationType;
                    if (altType !== undefined && def.alteredColor) {
                        var isAltered = false;
                        if (typeof GlyphAlteration !== 'undefined') {
                            if (altType === ALT.EMPOWER) isAltered = !!GlyphAlteration.isEmpowered(g.type);
                            else if (altType === ALT.BOOST) isAltered = !!GlyphAlteration.isBoosted(g.type);
                            else if (altType === ALT.ADDITION) isAltered = !!GlyphAlteration.isAdded(g.type);
                        }
                        if (isAltered) {
                            var c = def.alteredColor();
                            if (typeof c === 'string' && c.length > 0) {
                                if (altType === ALT.ADDITION) additionColor = c;
                                else boostColor = c;
                            }
                        }
                    }
                } catch (ex2) {}

                // Format primary + (optional) secondary value, with §…§ markers
                // and a ▲ prefix when this effect is in EMPOWER/BOOST altered state.
                var formatter = def.formatSingleEffect || def.formatEffect;
                var v = formatter ? formatter(eff.value) : String(eff.value);
                var vMarked = '§' + (boostColor ? '▲' : '') + v + '§';
                var v2 = '';
                if (def.conversion !== undefined) {
                    try { v2 = def.formatSecondaryEffect(def.conversion(eff.value)); } catch (ex3) {}
                }
                var v2Marked = v2 ? '§' + (boostColor ? '▲' : '') + v2 + '§' : '';

                // Description sourcing. `singleDesc` / `shortDesc` getters on
                // GlyphEffectConfig already resolve function values. Some raw
                // configs return raw strings; the `typeof === "function"` guard
                // covers both paths in case the fallback to raw config kicks in.
                var d = def.singleDesc || '';
                if (typeof d === 'function') d = d();
                // Preserve `[` and `]` (Swift renderer interprets them as the
                // addition-altered run, applies bold + addition color). Only
                // normalize newlines to a space and collapse tab/leading
                // whitespace that leaked from JS template literals.
                d = d.replace(/\n/g, ' ').replace(/[\t ]+/g, ' ').trim();
                effs.push(d.replace('{value}', vMarked).replace('{value2}', v2Marked));

                var sd = def.shortDesc || d;
                if (typeof sd === 'function') sd = sd();
                sd = sd.replace(/\n/g, ' ').replace(/[\t ]+/g, ' ').trim();
                shortEffs.push(sd.replace('{value}', vMarked).replace('{value2}', v2Marked));

                effBoostColors.push(boostColor);
                effAdditionColors.push(additionColor);
            }
        } catch (ex) {}
        return {
            effs: effs,
            shortEffs: shortEffs,
            effBoostColors: effBoostColors,
            effAdditionColors: effAdditionColors,
        };
    };
})();
