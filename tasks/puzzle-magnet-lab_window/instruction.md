# Puzzle Magnet Lab

Build **Puzzle Magnet Lab**, a 2D grid-based magnetic puzzle mini-game in Godot
4 in the current Pi working directory, unless the user explicitly specifies a
project or delivery path. In that case, build directly at the requested path.
The player manipulates polarity to push and pull
magnetic objects through a laboratory, solving spatial puzzles to guide an
energy core to the exit.

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

## Assets

2D assets are available read-only at these paths relative to the repository root:

- `assets/library/` — Kenney CC0 packs (sprites, tiles, UI, fonts).
- `assets/library-oga/` — OpenGameArt entries; respect each
  subdir's `LICENSE.txt`.

Browse the library and choose packs.
Copy what you need into your project's `assets/` folder.

## Project layout

The LTGD launcher keeps Pi's current working directory. Call
`godot_set_project` before editing: pass the user's explicit project or delivery
directory when given, or omit the path to create `game/` under Pi's current
directory. Put all Godot project files there. Relative project paths start from
Pi's current directory. From the repository root, the Godot console is at
`Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`.

```
game/    (default project directory; an explicit path takes precedence)
  project.godot
  Main.tscn
  scripts/  scenes/  assets/
```

From the repository root, set `$projectDir` to the actual game project directory
and confirm that it launches cleanly. Use the user's specified path when given:

```powershell
$projectDir = Join-Path (Get-Location).Path "game"  # use the explicit project path when given
& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --path $projectDir --quit-after 5
```

Use the Godot 4 command-line documentation for engine flags.

The Linux screenshot helper is not available in this Windows workflow. Inspect visuals in the Godot editor during manual playtesting.

Do not create demo input traces or replay scripts unless the user asks.
