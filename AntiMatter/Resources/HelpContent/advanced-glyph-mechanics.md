## Glyph Level Adjustment

Purchasable for **5000 Relic Shards**. Lets you set weights for each contributing resource (EP, DT, Replicanti, Eternities) — how much each affects the level of Glyphs you gain on Reality.

## Automatic Glyph Filtering

Purchasable for **2e10 Relic Shards**. Assigns a score to each Glyph choice and picks the highest, then compares against a threshold and either keeps it or sacrifices it. The basic modes:

- **Lowest total sacrifice** — score = how much sacrifice value you have of that Glyph's type. Glyph types with the *lowest* sacrifice total get the highest score. No threshold; always sacrifices.
- **Number of effects** — score = number of effects. Ties broken by higher rarity. Threshold is a number you type.
- **Rarity Threshold** — score = rarity %. Threshold is set per Glyph type.

Two advanced modes:

- **Specified Effect** — score = rarity, compared against your rarity threshold, but the score drops by **200** per missing required effect. Lets you require certain effects and a minimum effect count. Setting impossible conditions (e.g. 6 effects on a Power Glyph) forbids that Glyph *type* from being selected.
- **Effect Score** — score = rarity + per-effect bonuses you configure. Useful tricks:
  - Give a weaker effect a value of **5** to keep Glyphs without it as long as they're rare enough to compensate.
  - Set a large negative score on an unwanted effect to forbid Glyphs with it.
  - Set an impossible condition (threshold **999** with all effects worth **0**) to forbid entire types.

The Glyph Filter mode is **global** — you can't filter Power Glyphs with one mode and Time Glyphs with another. Each filter mode remembers its own settings if you switch.

Unlocking the Glyph Filter also exposes the *highest Glyph score among your upcoming choices* as a comparable currency in the Automator. You can make the Filter force an immediate Reality (once available) if no upcoming choice would be kept — as long as the Reality autobuyer is on.

## Glyph Presets

Purchasable for **1e14 Relic Shards**. Adds **7** slots that save your currently equipped Glyphs as a "preset". You cannot overwrite a slot; delete it first. Loading a preset finds each saved Glyph in your inventory and equips it. If any Glyph in the preset can't be found, a warning shows and the rest equip anyway.

When loading you can be **Level** and/or **Rarity** sensitive. The best Glyph that matches the preset's requirements will be the one equipped. Tap any group of circular Glyphs to bring up a summary of the whole set.
