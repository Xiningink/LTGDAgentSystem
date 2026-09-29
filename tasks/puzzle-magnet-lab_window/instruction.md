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

The LTGD launcher normally starts Pi in `games/system/`. This is the default
writable game project directory. If Pi starts in another project directory, use
that current directory instead; an explicit project or delivery path in the
user's request takes precedence. Paths in this section are relative to the
repository root. The Godot console is at
`Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`.

```
games/system/    (default project directory)
  project.godot
  Main.tscn
  demo_outputs/    ← your input traces (1–10 files)
  scripts/  scenes/  assets/
```

From the repository root, the default project must launch cleanly with the
following PowerShell command. If the user specified another project or delivery
path, use that path after `--path`:

```powershell
& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --path .\games\system --quit-after 5
```

Use the Godot 4 command-line documentation for engine flags.
**Engine flags like `--headless` and `--quit-after N` must come BEFORE `--`** —
anything after `--` is forwarded to the project as user args and silently
ignored by the engine. Correct shape:
`& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --quit-after 5 --path .\games\system -- --scenario near_victory`.

The Linux screenshot helper is not available in this Windows workflow. Inspect visuals in the Godot editor during manual playtesting.

## Demos

Ship **1–10 input-trace files** under the project's `demo_outputs/` directory
(`games/system/demo_outputs/` by default), one per demo, each named `*.json`.
The local GameEva replayer launches a fresh game per trace and replays
synthetic mouse and keyboard input at 1280×720. It saves replay logs, but
does not capture or score video. Only the first 10 traces by filename are
replayed locally.

### Scenarios

Normal play should start from the title screen and demonstrate the task's
core gameplay loop.
Demo playback must be deterministic. For demos that need a specific state
(a specific level, combat state, upgrade screen, result state, or late-game
setup), define named scenarios your game loads when launched with:

```powershell
& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --path .\games\system -- --scenario <id>
```

When `--scenario <id>` is present the game must skip menus, set up the named
state deterministically (seed any RNG), and begin accepting input immediately.

### Trace file format

```json
{
  "scenario": "title_flow",
  "duration_frames": 360,
  "events": [
    {"frame": 30,  "type": "mouse_click", "button": "left", "x": 300, "y": 360},
    {"frame": 90,  "type": "key_press",   "keycode": "1"},
    {"frame": 180, "type": "key_press",   "keycode": "SPACE"},
    {"frame": 300, "type": "wait"}
  ]
}
```

- `scenario` — optional; omit for a normal game launch from the title screen.
- `duration_frames` — total frames to record at 30 fps; cap at **600 (20 s)**.
- `events` — time-ordered inputs. Coordinates are pixels in the 1280×720
  viewport. Supported types:
  - `mouse_click`: `{frame, type, button: "left"|"right", x, y}`
  - `mouse_down` / `mouse_up`: `{frame, type, button: "left"|"right", x, y}` —
    use these for drag interactions: emit `mouse_down` at the start point,
    one or more `mouse_move` events along the way, and `mouse_up` at the end.
    A `mouse_click` is a `mouse_down` + `mouse_up` at the same point in tight
    succession.
  - `mouse_move`: `{frame, type, x, y}`
  - `key_press` / `key_down` / `key_up`: `{frame, type, keycode}` — keycodes:
    `A`–`Z`, `0`–`9`, `ESCAPE`, `ENTER`, `SPACE`, `TAB`, `BACKSPACE`,
    `DELETE`, `SHIFT`, `CTRL`, `ALT`, `UP`, `DOWN`, `LEFT`, `RIGHT`.
  - `wait`: `{frame, type}` — anchor frame, no input.

Replay must be deterministic: same trace, fresh launch, same outcome every time.
