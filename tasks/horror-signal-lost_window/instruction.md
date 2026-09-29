# Horror Signal Lost

Build a **Horror Signal Lost** game in Godot 4 at `.\output\game`.
This is not a prototype. It is a **complete, shippable micro-game** that could
sit on an itch.io page or Steam as a polished vertical slice.

## Core Vision

The player is a radio operator in a remote station, triangulating distress signals
from ships and outposts while something unseen jams the frequencies. The fantasy
is isolation and dread: alone in a dark room with only static and voices, piecing
together what is happening outside while the interference grows more aggressive
and personal. Tension comes from battery management — the radio drains power, and
darkness invites the presence closer. Each signal triangulated reveals a piece of
the horror unfolding beyond the walls.

## What the Player Experiences

1. **Title Screen** — A dark screen with the game name flickering like a dying
   signal, static noise visual effects, and a play button styled as a radio dial.
2. **The Radio Station** — A single-room view of the operator's desk: radio
   equipment, a map with pins, a battery gauge, and a window showing darkness
   outside. The room is lit by the radio's glow.
3. **Signal Scanning** — The player tunes a frequency dial (horizontal slider) to
   find distress signals hidden in static. When a signal locks, audio crackles
   and a transcript appears. Each signal gives coordinates.
4. **Triangulation** — The player places pins on the map based on signal
   coordinates. Connecting three or more pins reveals the source location and
   advances the story. The map fills with pins over time.
5. **Jamming Entity** — Periodically, interference spikes. The screen distorts,
   the radio emits unsettling sounds, and the player must quickly retune to
   escape the jamming. Failing causes battery drain and screen corruption.
6. **Battery Management** — The radio consumes battery. A gauge depletes over
   time. The player can reduce power (dimming the room, limiting scan range) to
   conserve. Batteries are found by solving signal puzzles. If power dies, the
   room goes dark and the entity approaches.
7. **Escalation** — As more signals are triangulated, the jamming grows worse,
   signals become more disturbing, and the window shows shapes moving outside.
   The final signal reveals what is hunting the player.

## Assets

2D assets are available read-only at these paths relative to the repository root:

- `assets/library/` — Kenney CC0 packs (sprites, tiles, UI, fonts).
- `assets/library-oga/` — OpenGameArt entries; respect each
  subdir's `LICENSE.txt`.

Browse the library and choose packs.
Copy what you need into your project's `assets/` folder.

## Project layout

The LTGD launcher keeps Pi's current working directory. Call
`godot_set_project` with `project: "output/game"` before editing, and put all
Godot project files there. Relative project paths start from Pi's current
directory. From the repository root, the Godot console is at
`Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`.

```
.\output\game
  project.godot
  Main.tscn
  scripts/  scenes/  assets/
```

From the repository root, confirm that the specified game project launches cleanly:

```powershell
$projectDir = Join-Path (Get-Location).Path "output\game"
& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --path $projectDir --quit-after 5
```

Use the Godot 4 command-line documentation for engine flags.

## Visual check

A Windows screenshot helper is available at
`LTGDAgentSystem/tools/screenshot.ps1`. Use it to actually inspect the title
screen, radio station, and late-game or result
screens. Run it from the game project directory, then use Pi's `read` tool on
each saved PNG. A headless launch does not show what these screens look like.

From the repository root:

```powershell
Push-Location .\output\game
try {
    & ..\..\LTGDAgentSystem\tools\screenshot.ps1 -Out ..\title.png -Frames 60
    & ..\..\LTGDAgentSystem\tools\screenshot.ps1 -Out ..\signal_scan.png -Frames 120 -Scenario signal_scan
} finally {
    Pop-Location
}
```

Use Pi's `read` tool on `output/title.png` and `output/signal_scan.png`. For
`-Scenario signal_scan`, the game must read `--scenario signal_scan` from
`OS.get_cmdline_user_args()` and enter that state. Use another scenario ID when
checking a different state. The helper reads the project from the current
directory, so no `-Project` argument is needed here.

Do not create demo input traces or replay scripts unless the user asks.
