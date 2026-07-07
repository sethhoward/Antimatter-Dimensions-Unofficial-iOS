The Automator runs scripts that drive the game for you. Once unlocked, it can buy dimensions, trigger prestiges, wait for milestones, and loop indefinitely — useful for the long stretches of late-game where you'd otherwise be tapping the same buttons every few seconds.

## Unlocking

The Automator unlocks at **100 Automator Points**. Points come from specific Perks, specific Reality Upgrades, the number of Realities you've completed (+2 per Reality, up to 50), and unlocking Black Holes (+10). The Automation tab shows your current breakdown.

Until you reach 100 points, the Automation tab displays a progress screen with every source listed — green for sources you've already earned, red for ones you haven't. Once you hit 100, the screen flips over to the editor.

## Using the Editor

The Automator tab has three areas:

- **Editor** — write or modify scripts. Syntax highlighting is built in.
- **Scripts** — switch between scripts, rename them, or create a new one. Each save slot has its own script library.
- **Errors / Log / Docs** — switch the right-hand panel between the in-progress error list, the execution log, and the full command reference.

Use the play / pause / step / rewind controls at the top of the editor to run a script. "Follow execution" auto-scrolls the editor to highlight the currently-running line.

## Commands

The full command reference lives **inside the Automator tab** in the **Docs** panel — open the Automator and tap the panel toggle. Commands include things like `buy dimension`, `wait pending completions`, `if currency >= value`, `start ec`, `unlock dilation`, and dozens more. Every command is documented with its parameters, an example, and the surrounding category.

The Docs panel is the canonical place for command syntax; we don't duplicate it here so the two pages can't get out of sync.

## Importing and Exporting Scripts

Scripts are stored in your save, but you can also share them.

- **Export** — copies the currently-selected script to the clipboard as a long Base64 string starting with `AntimatterDimensions`. Paste it into a notes app or send it to a friend.
- **Import** — paste a script string into the import prompt. The game shows a preview (script name, line count, defined constants and presets, any errors) before you commit. You can also choose whether to import the script's constants.

Imports come from the clipboard, so anything you paste from the web version's export works on iOS, and vice versa.

## Speed

Each Reality you complete makes the Automator tick faster (more commands per second). The current rate is shown at the bottom of the unlock screen and in the editor's status bar after you've unlocked it.
