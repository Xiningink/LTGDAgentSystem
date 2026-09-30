# Horror Signal Lost

A single-room horror micro-game for Godot 4.6. You are the night operator of
Station K-7, a coastal radio relay. Tune the receiver, pull distress signals out
of the static, plot their coordinates on the chart, and triangulate what is out
there - before the power runs out and the thing on the band finds you.

## Running

Open the folder in Godot 4.6 and press play, or from the command line:

```
Godot_v4.6.2-stable_win64_console.exe --path . --resolution 1280x720
```

First launch after copying the project should run an import pass
(`--headless --import --path .`) so Godot builds its resource cache.

## Controls

| Input | Action |
| --- | --- |
| Drag the dial, drag the spectrum, or mouse wheel | Tune the receiver |
| Left / Right arrow keys | Fine tune |
| Click a power stage button | Standby / Low / Med / High |
| Click the chart | Plot the coordinate from the log |
| Click a log chip | Re-read a recovered transcript |
| Click `CELL xN` | Burn an emergency power cell |
| Click the speaker icon | Mute |

## How a watch plays out

1. **Tune.** Each chapter hides three carriers somewhere in the 88-108 MHz band.
   Turning the dial onto one and holding it fills the carrier lock meter. Higher
   power stages widen the lock window but drain the battery faster.
2. **Log.** Every locked carrier types out a transcript and a coordinate.
3. **Plot.** Click the chart where the coordinate falls. The chart shows a
   `WARM` / `LOCK` proximity hint, so being roughly right is enough.
4. **Triangulate.** Three plotted pins pull taut, cross at a point, and reveal
   the source. Every completed triangulation awards power and a spare cell.
5. **Survive.** Jamming spikes tear the screen apart; find the clear channel and
   hold it. Failures drain the battery and push the presence meter up. At zero
   power the room goes dark and the emergency cells are all that is left.

Four chapters, three endings, and one carrier that is always closer than it
looks.

## Project layout

```
project.godot
Main.tscn                 root controller, CRT post pass, scenario hooks
scenes/                   TitleScreen, StationScreen, EndingScreen
scripts/
  main.gd
  palette.gd, uikit.gd    shared colour language and draw helpers
  autoload/               GameState, SignalDB, Audio director
  ui/                     room, window, chart, receiver, HUD, log, modal
  screens/                screen controllers
  tests/selftest.gd       headless checks for the state machine
assets/                   fonts, UI, map, icons, FX, audio, shaders
```

## Verification hooks

Scenarios are read from `OS.get_cmdline_user_args()` and are useful for
screenshots and automated checks:

```
-- --scenario title|station|signal_scan|map|jamming|triangulation
              |chapter2|chapter3|near_victory|blackout|final
              |ending|consumed|dark|selftest|uitest|enterstation
```

- `selftest` runs 174 assertions over the signal database, coordinates,
  progression, power economy, blackouts and endings.
- `uitest` drives the real dial, chart and HUD code paths.
- `enterstation` plays the title-to-station transition and checks a clean start.

```
Godot_v4.6.2-stable_win64_console.exe --headless --path . -- --scenario selftest
```

## Credits

See `CREDITS.md`. All art and audio is CC0 (Kenney, OpenGameArt contributors) or
generated for this project.
