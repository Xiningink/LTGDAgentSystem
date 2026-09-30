# Ivory Beats

A 2D vertical rhythm-reaction arcade game for **Godot 4.6**.

A relentless cascade of dark tiles rushes down a stark monochrome grid. Shatter
each one at the exact moment it crosses the strike line. One wrong lane or one
escaped tile ends the run instantly.

## Controls

| Action | Input |
| --- | --- |
| Strike lane 1–4 | `A` `S` `D` `F`, `1` `2` `3` `4`, or click a lane |
| Start / confirm | `Enter`, `Space`, or any lane |
| Move mode selection | `↑` `↓` / `←` `→` |
| Retry (results) | `Enter`, `Space`, `R`, or the **RETRY** button |
| Back to menu | `Esc`, `M`, or the **MENU** button |

## Modes

- **SPRINT** — clear 40 tiles before the 28-second clock empties.
- **ENDLESS** — survive an ever-accelerating scroll. Speed has no ceiling
  that matters; it only ends when you miss.
- **BLITZ** — a tight 20-second countdown. Every tile counts.

Personal bests are stored in `user://ivory_beats.save.json`.

## Running

```powershell
Godot_v4.6.2-stable_win64_console.exe --path .\output\game
```

Headless smoke test:

```powershell
Godot_v4.6.2-stable_win64_console.exe --headless --quit-after 5 --path .\output\game
```

## Scenarios

Named states can be launched directly for screenshots and automated checks:

```powershell
Godot_v4.6.2-stable_win64_console.exe --path .\output\game -- --scenario near_victory
```

Available ids: `title`, `ready`, `showcase`, `showcase_sprint`, `showcase_blitz`,
`endless`, `sprint`, `blitz`, `near_victory`, `results`, `game_over`.

Use `--seed <int>` for deterministic tile layouts.

## Structure

```
Main.tscn
scripts/          game controller, board simulation, global managers, UI
scenes/           Board / TitleScreen / Hud / ResultsPanel scenes
assets/           Kenney CC0 fonts and audio, pattern-pack-lines backdrop
```

## Credits

Type and sound effects: Kenney (CC0). See the `LICENSE-*.txt` files in
`assets/`.
