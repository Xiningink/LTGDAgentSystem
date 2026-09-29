# Racing Trick Runner

Build a Racing Trick Runner in Godot 4 in the current Pi working directory,
unless the user explicitly specifies a project or delivery path. In that case,
build directly at the requested path.
This is not a prototype. It is a **complete, shippable micro-game** that could
sit on an itch.io page or Steam as a polished vertical slice.

## Core Vision

An endless downhill runner where the player carves through procedurally varied
terrain, launching off ramps to perform aerial tricks that boost speed and
score. The slope never ends — the challenge is how far you can go before
crashing. Weather shifts from sunshine to blizzard, day cycles to night, and
the terrain grows steeper and more treacherous. Tricks are the key to survival:
they refill a boost meter that lets you power through flat sections. Unlockable
characters with different trick styles and visual flair provide long-term goals.

## What the Player Experiences

1. **Title Screen** — A snowy mountain vista with the game name in a frosty
   stylized font, a silhouetted rider mid-backflip, and Play/Collection
   buttons. No plain Godot grey.
2. **The Run** — Side-scrolling endless descent. The character automatically
   moves downhill; the player controls jump timing, trick execution, and
   landing angle. Terrain scrolls with parallax mountain backgrounds.
3. **Trick System** — While airborne, the player inputs trick commands (flip,
   spin, grab) using directional keys. Each trick has a point value and a
   time cost. Landing cleanly after a trick awards points and refills boost.
   Landing badly (wrong angle) causes a stumble that costs speed.
4. **Boost Mechanic** — A boost meter fills from successful tricks. Activating
   boost increases speed dramatically with a visual trail effect. Boost is
   essential for clearing flat sections and gaps.
5. **Weather and Day/Night** — Conditions change during a run: clear skies
   transition to fog (reduced visibility), then snow (slippery terrain), then
   blizzard (both). Day fades to night with reduced visibility. Each condition
   affects gameplay and visuals distinctly.
6. **Obstacles and Terrain** — Rocks, trees, and crevasses appear as obstacles.
   The terrain varies between smooth slopes, mogul fields, cliff drops, and
   ramp sequences. Hitting an obstacle ends the run.
7. **Character Collection** — At least 5 unlockable characters earned by
   reaching distance milestones or score targets. Each has a unique sprite,
   trick animation style, and one special ability (higher jumps, longer boost,
   extra hit point).

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
