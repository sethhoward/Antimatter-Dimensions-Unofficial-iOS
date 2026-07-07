The **Black Hole** speeds up the game on a periodic cycle. The game runs at normal speed for some duration, then has a burst of extremely fast play for a short period, then returns to normal — repeating.

Black Hole speedups are much stronger than tickspeed because they affect *everything equally*, including things only partly affected by tickspeed (Infinity / Time Dimensions), things normally unaffected (DT/TT generation), and time-spent effects (idle path IP/EP multipliers).

While most features are sped up, some specifically refer to **real time** rather than **game time** — for example the Perks that auto-complete Eternity Challenges over time. Anywhere it doesn't specify, assume **game time**. Note that this also matters for things where you'd *prefer* lower time spent (e.g. the Reality Upgrade "Replicative Rapidity").

## Upgrades

Black Hole upgrades cost **Reality Machines**. There are three per Black Hole:

- **Interval** — how long the Black Hole stays inactive between bursts. **−20%** per upgrade.
- **Power** — how much faster the game runs during a burst. **+35%** per upgrade.
- **Duration** — how long each burst lasts. **+30%** per upgrade.

## Second Black Hole

**100 days** of *game time* after unlocking the first Black Hole, you can buy a Reality Upgrade for a second Black Hole. The timer on Black Hole 2 only advances while Black Hole 1 is active. For example: BH1 has a 4-minute duration and BH2 has an 8-minute interval — BH2 only activates every two cycles of BH1, no matter how short BH1's interval is. The header readout already factors this in; the Black Hole tab also shows how much BH1-active time is needed for BH2 to activate.

## Permanence

When a Black Hole is active for at least **99.99%** of the time, it becomes permanently active. Tracked separately per Black Hole.

## Offline behaviour

Black Hole cycles continue normally while offline, and their speed boosts apply fully as if the game were running. Offline simulation uses different tick lengths for inactive vs active periods to reduce inaccuracy during bursts. See **Offline Progress** for more.

## Pause / Unpause

Black Holes can be paused, halting their interval/duration cycle. Unpausing takes **5 real-time seconds** to reach max speed (the acceleration time still advances the cycle, so pausing ultimately loses some boosted time). Both Black Holes pause/unpause together. The Black Hole tab has a toggle to automatically pause them **5 real-time seconds** before activation.

## Upgrade costs

- **Interval** — Base **15 RM**, ×**3.5** per upgrade.
- **Power** — Base **20 RM**, ×**2** per upgrade.
- **Duration** — Base **10 RM**, ×**4** per upgrade.

Above **1e30 RM** the cost multiplier between purchases increases by an additive **+0.2** per upgrade. Above **1.8e308 RM**, a new scaling takes over: upgrades behave as if their initial cost were **1e310** and the multiplier grows from **×1e6** to **×1e7** to **×10** between successive purchases.

**Black Hole 2:** all upgrades have an initial cost **×1000** higher than Black Hole 1, with the same cost multipliers.
