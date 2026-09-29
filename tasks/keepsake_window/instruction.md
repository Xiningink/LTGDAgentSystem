# Keepsake

Build **Keepsake**, a quiet memory-reconstruction visual novel about sorting a
late person's belongings, in Godot 4 in the current Pi working directory,
unless the user explicitly specifies a project or delivery path. In that case,
build directly at the requested path. This is not a
prototype. It is a **complete, shippable micro-game** that could sit on an
itch.io page or Steam as a polished vertical slice.

## Core Vision

Someone has died, and you have been asked to sort through what they left behind.
A faded photograph, a folded letter, a worn ring, a diary with a torn-out
page — each object holds a fragment of a life, and they do not give up their
meaning in order. Keepsake is a **choice-driven visual novel of reconstruction**
where the player examines the keepsakes of a stranger and, piece by piece and
out of sequence, assembles the story of who this person really was — and the
quiet secret time had buried with them.

The fantasy is **piecing together a life from the things it left behind**. The
heart of the loop is **examine, remember, connect, understand** — turning a
keepsake over, hearing the memory it stirs, and fitting it against what you have
already found until a hidden shape emerges. The order the player chooses, and
how they come to read an ambiguous choice the dead made, shape the
understanding they arrive at. It should feel like a slow, tender, melancholy
piece with real emotional weight and more than one way to understand a life, not
a single linear obituary read start to finish.

## What the Player Experiences

1. **An Authored Opening** — From a styled title the player is given their
   task — a room, a box, a life's worth of objects to sort — established as a
   quiet illustrated scene with narration that sets the mood and the absence at
   its center.
2. **Examining the Keepsakes** — The player chooses which object to take up,
   in whatever order they like, and each keepsake is examined as an illustrated
   item with the memory or fragment of the past it reveals. The room of
   belongings is something the player works through at their own pace, not a
   fixed slideshow.
3. **Fragments That Connect** — Each examined keepsake adds a remembered
   fragment to what the player knows, and fragments fit against one another:
   a date on a letter explains a photograph, an object's absence answers an
   earlier question. The player feels a life assembling out of order, and what
   they have already found colors how the next piece reads.
4. **A Choice of Understanding** — As the picture comes together the player
   reaches moments of interpretation — how to read an ambiguous decision the
   dead person made, what to believe about a secret, whether to judge or
   forgive. These choices are deliberate and remembered, and what the player has
   uncovered shapes which understandings are even available.
5. **More Than One Way to Remember** — The piece resolves into one of several
   genuinely different closing understandings — a life redeemed, a secret kept
   in kindness, a quiet grief, a truth that recasts everything — each reached
   through which fragments the player found and how they chose to read them,
   and shown as an authored, styled conclusion that names the understanding they
   came to. The player can begin again and arrive somewhere else.

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
