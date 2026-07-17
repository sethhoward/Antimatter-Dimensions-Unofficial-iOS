Antimatter Dimensions has a catch-up mechanic that simulates the game's behaviour while it was closed. The simulation is only approximately accurate — the math is too complex to run at full fidelity in a reasonable time — and at the end you'll see a summary of how things changed while you were gone.

If the game is open but the app gets suspended for a long period, returning to it will trigger the same offline catch-up. This can be unreliable across devices; if you'd rather have the missed time applied as a single tick, you can disable offline progress in **Options → Gameplay Options**.

## Ticks

The game updates once per "tick": Dimensions produce, autobuyers fire, multipliers recalculate, and the UI refreshes. The default is roughly **30 ticks per second**, configurable in Options.

During offline catch-up, ticks are stretched to span the time you were away. With **1000** offline ticks and an hour of absence, each simulation tick covers about **3.6 seconds** of game time. For most resources this produces nearly identical results to running live, but autobuyers will only fire once every 3.6 seconds during the catch-up — meaningful at points in the game where rapid autobuyer activity matters.

## Tick count

Offline tick count is adjustable in **Options → Gameplay Options**, between **500** and **1,000,000**. Lower counts simulate faster but less accurately; higher counts are more accurate but take longer. A single tick can cover at most one day of game time, so very long absences (over a year) may not fully catch up.

iOS also caps the simulator at **10,000 effective ticks per session** regardless of the slider — JavaScriptCore on iOS doesn't have a JIT compiler, and uncapped late-game sims become unusable. If a catch-up is taking too long, the on-screen progress bar offers **Speed up** (halve remaining ticks) and **Skip** (jump to the last 10) buttons.

## Black Hole behaviour offline

Once the Black Hole is unlocked, the simulator runs game time per tick rather than real time per tick. This may make Black Holes appear to be active for more of the catch-up than they really are, but the game is running active periods more slowly and skipping past inactive ones because they contribute less production. The result is generally in your favour compared to constant-real-time ticks.

## Turning it off

Offline progress can be disabled entirely (Options → Gameplay Options) — for diagnostic purposes, or for an "online only" playthrough. While disabled, total time played also pauses when the app is closed.
