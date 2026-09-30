# Puzzle Magnet Lab

A turn-based, grid-based magnetic logic puzzle built with **Godot 4.6**
(GL Compatibility renderer).

Every chamber is a closed system of magnets, metal crates, pressure plates,
gates, inverters and live hazards. Nothing moves on its own: you commit one
tile of movement per turn and the whole room reacts.

## Running

```powershell
# from the repository root
.\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --path .\output\game
```

## Controls

| Input | Action |
| --- | --- |
| `WASD` / arrow keys | move one tile |
| mouse click on an adjacent tile | move one tile |
| `Z` | undo (unlimited) |
| `R` | reset the chamber |
| `H` or `Esc` | rules / menu overlay |
| `Enter` / `Space` | confirm (start, next chamber) |

## Rules

1. **Metal crates** are inert. They are shoved one tile at a time, chain into
   other crates, press plates, and are consumed when shoved into a live hazard
   (which shorts the hazard out permanently for the rest of the attempt).
2. **Magnets** carry one polarity, and your core carries its own field.
   - *Same polarity*: the magnet is **repelled** ahead of you. Whatever it
     strikes receives the same shove, so a row of matching magnets cascades.
   - *Opposite polarity*: the two of you **swap** tiles, pulling the magnet
     onto the tile you just left.
3. **Your core cannot enter a live hazard**; magnets pushed into one burn away.
4. **Inverter pads** flip your own polarity for the rest of the attempt. Step
   on one again to flip back.
5. **Gates** are open while every plate sharing their letter is held down by
   you or by an object. Objects can hold a plate; you cannot be in two places.
6. **Reach the airlock** (the green portal) to tag the chamber. Solid matter is
   refused entry, so the portal must be approached, never blockaded.

Stars are awarded from move efficiency against the chamber's **par**, the
shortest known solution.

## Project layout

```
project.godot     Godot 4.6 project (autoloads, window, renderer)
Main.tscn         entry scene - the screen router
scripts/
  main.gd         screen routing, input map, screenshot scenarios
  sim.gd          the whole rule set, headless and side-effect free
  board.gd        chamber view: procedural art, animation, effects
  levels.gd       chamber manifest loader
  palette.gd      shared colour language
  ui_kit.gd       style boxes, buttons, labels, star rating
  sfx.gd          pooled sound bank (autoload "Sfx")
  save.gd         progress + preferences (autoload "Save")
  backdrop.gd     animated laboratory background
  field_art.gd    traced dipole field lines for the title screen
  rule_icon.gd    illustrated rule diagrams
  star_icon.gd    geometry star (no glyph dependency)
  level_card.gd   chamber index card
  screens/        title, level select, gameplay, help
scenes/
  Title.tscn, LevelSelect.tscn, Gameplay.tscn, Help.tscn
                  standalone launchers for a single screen, e.g.
                  --scene res://scenes/Help.tscn
assets/
  levels.json     the 16 chambers + 4 chapters (map art, hints, par)
  fonts/          Kenney Future / Mini Square
  ui/             Kenney sci-fi UI pack (glass panels, buttons, crosshair)
  sfx/            Kenney interface / impact / sci-fi / jingle sounds
  shaders/        backdrop shader
```

## Screenshot / QA scenarios

`Main.gd` understands a few user arguments (everything after `--`), which the
workspace screenshot helper passes through:

```powershell
& ".\tools\screenshot.ps1" -Project ".\output\game" -Out "$env:TEMP\shot.png" `
    -Frames 60 -Scenario cascade
```

| Scenario | Shows |
| --- | --- |
| `title` (default) | title screen |
| `levels` | chamber index |
| `help` | field manual |
| `play` / `level_6` | a chamber (`level_N` is 1-based) |
| `near_victory` | 1-1 with the plate held and the core two tiles from the airlock |
| `victory` | victory overlay |
| `mid` | 3-1 mid-cascade |
| `cascade` | a live repulsion chain |
| `burn` | a live hazard short-out |
| `final` | the last chamber |

## Verification

`output/dev/selftest.gd` replays the shortest known solution for all sixteen
chambers through the shipped `sim.gd` and asserts the core reaches the airlock
in exactly the published par, plus rule-isolation probes (metal crates cannot
shove magnets, hazards swallow crates, every gate has plates and starts
sealed):

```powershell
.\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --headless --path .\output\game `
    --script .\output\dev\selftest.gd
```

`output/dev/solve.py` is the reference BFS solver that produced the solutions
and par values baked into `assets/levels.json`; it mirrors `sim.gd` rule for
rule.

## Assets

Art and audio come from the workspace library (Kenney CC0 packs) — see
`assets/CREDITS.md`. All board, entity, hazard, gate and portal artwork is
drawn procedurally at runtime so it stays crisp at any resolution and can
react to game state.
