# Puzzle Magnet Lab

Build **Puzzle Magnet Lab**, a 2D grid-based magnetic  in Godot 4 at `.\output\game`

This is not a prototype. It is a **complete, shippable micro-game** that could
sit on an itch.io page or Steam as a polished vertical slice.

## Core Vision

The game is a turn-based spatial logic puzzle built on one central rule:
opposite polarities attract, same polarities repel. Every level is a closed
system of magnets, metal crates, gates, and hazards where the player must
reason about chain reactions before committing a move. The tension comes from
irreversibility and cascading consequences: flipping a polarity switch might
solve one gate while slamming a crate into a hazard. The best version feels
like a miniature physics sandbox wrapped in clean laboratory aesthetics, where
each puzzle teaches a new interaction between familiar magnetic rules.

## What the Player Experiences

A title screen sets the laboratory tone with magnetic imagery and a clear way
to begin. The player enters a grid-based puzzle chamber where walls, floor
tiles, magnetic crates, polarity indicators, switches, gates, and an exit are
all readable at a glance. Movement is deliberate, one tile at a time, and the
grid enforces strict spatial reasoning.

Early puzzles teach the basics: push a same-polarity crate out of the way, or
pull an opposite-polarity block onto a pressure plate to open a gate. As the
player progresses, levels layer mechanics together. A polarity-swap switch
inverts the player's field, turning a repulsion problem into an attraction
opportunity. Hazard tiles punish careless moves. Multi-step sequences demand
planning several moves ahead, where an early push sets up a later pull across
the room.

An undo or reset option keeps frustration in check. When the core reaches the
exit, a completion screen celebrates the solve and offers the next challenge.
Failure states are clear and recoverable. The arc moves from simple single-crate
rooms to intricate multi-gate chambers that require the full toolkit of push,
pull, swap, and sequencing.

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
