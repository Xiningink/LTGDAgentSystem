# Ivory Beats

Build **Ivory Beats**, a 2D vertical rhythm-reaction arcade game in Godot 4 at
`\output\game`. This is not a prototype. It is a **complete, shippable
micro-game** that could sit on an itch.io page or Steam as a polished vertical
slice.

## Core Vision

A relentless cascade of dark tiles rushes down a stark monochrome grid, and the
player must shatter each one at the exact moment it crosses the strike line.
The tension is pure reaction speed married to lane-switching rhythm: four lanes
mean four possible targets every beat, and a single mistap or missed tile ends
the run instantly. The game rewards flow state — that trance where fingers move
faster than conscious thought and the score counter blurs upward. Between
attempts the player chases personal bests across multiple modes that each twist
the pressure differently: race to clear a target count, survive an ever-
accelerating scroll, or maximize hits within a countdown. The aesthetic is
sleek modernist minimalism — a crisp black-and-white grid punctuated by neon
feedback flashes whenever a tile shatters.

## What the Player Experiences

A clean title screen presents the game name and a mode-select menu showing
personal-best scores loaded from a save file. The player picks a challenge mode
and lands on a frozen four-lane grid with a pulsing prompt inviting the first
tap.

The moment the player acts, tiles begin scrolling. Dark tiles descend one per
row, each in a random lane, and the player hammers lane keys or clicks to
destroy the lowest active tile before it escapes the bottom. Every successful
hit vaporizes the tile with a neon flash, nudges the score, and pulls the next
row into position. The rhythm builds — slow and approachable at first, then
quickening until fingers blur.

A wrong-lane tap or an escaped tile triggers instant defeat: the board locks,
the faulted tile flashes red with a screen shake, and a results panel slides
over the frozen grid. The panel shows the run's score against the saved best,
updates the record if beaten, and offers an instant retry that resets the board
without relaunching.

Each mode reshapes the pressure: one races to clear a fixed tile count against
the clock, another accelerates the scroll every few successful hits until the
player breaks, and a third imposes a tight countdown where every tile counts.
The loop is short, punchy, and endlessly replayable.

## Engine & Assets

From the repository root, 

the Godot engine is at `Godot_Engine\Godot_v4.6.2-stable_win64.exe` 

the Godot console is at `Godot_Engine\Godot_v4.6.2-stable_win64_console.exe`.

2D assets are available read-only at these paths relative to the repository root:

- `assets/library/` — Kenney CC0 packs (sprites, tiles, UI, fonts).
- `assets/library-oga/` — OpenGameArt entries; respect each
  subdir's `LICENSE.txt`.

Browse the library and choose packs.
Copy what you need into your project's `assets/` folder.

## Project layout

```
.\output\game
  project.godot
  Main.tscn
  scripts\
  scenes\
  assets\
```

From the repository root, set `$projectDir` to the actual game project directory
and confirm that it launches cleanly. Use the user's specified path when given:

```powershell
$projectDir = Join-Path (Get-Location).Path "output\game"
& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --path $projectDir --quit-after 5
```

A reference for Godot CLI flags is at `.\tools\godot_command_line.md`.
**Engine flags like `--headless` and `--quit-after N` must come BEFORE `--`** —
anything after `--` is forwarded to the project as user args and silently
ignored by the engine. From the repository root, the correct shape is:
`.\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --quit-after 5 --path .\output\game -- --scenario near_victory`.

A screenshot helper is available at `.\tools\screenshot.ps1`. Use it to actually see what your UI / battlefield / result screens look like.

```powershell
& ".\tools\screenshot.ps1" `
    -Project ".\output\game" `
    -Out "$env:TEMP\frame.png" `
    -Frames 60
```

To screenshot a specific scenario, pass `-Scenario <id>` to the PowerShell
helper. The helper accepts `-Project` , `-Out`, `-Frames`, `-Scene`, and `-Scenario` as
PowerShell parameters. Additional game arguments can be passed through
`-GameArgs` and remain available to the game through
`OS.get_cmdline_user_args()`.

```powershell
& ".\tools\screenshot.ps1" `
    -Project ".\output\game" `
    -Out "$env:TEMP\signal_scan.png" `
    -Frames 120 `
    -Scenario "signal_scan"
```
