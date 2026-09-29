# LTGD workspace rules

- The user enters game requirements as natural language in Pi. Keep Pi conversation as the product entry point.
- Keep the Pi source under `PiAgent/` and the LTGD-specific extension and launcher under `LTGDAgentSystem/`. The LTGD launcher calls `PiAgent/pi-test.ps1` with `--extension`. Follow `PiAgent/AGENTS.md` for Pi source changes.
- Use the user's selected output directory for generated games; otherwise use `game/` under Pi's current directory. Godot verification results remain in the Pi session. Do not edit shared `assets/` or `Godot_Engine/` while generating a game.
- The original `../GameEva/` repository is a migration reference. Do not rewrite its history or delete it as part of this workspace cleanup.
- Commit each completed workspace change by default with a descriptive message. Stage only files changed for that modification.
