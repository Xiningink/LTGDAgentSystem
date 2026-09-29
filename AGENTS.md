# LTGD workspace rules

- The user enters game requirements as natural language in Pi. Keep Pi conversation as the product entry point.
- Keep the LTGD-specific extension and CMD launcher under `LTGDAgentSystem/`. The launcher calls the installed `pi` command with `--extension`; normal use does not require a local `PiAgent/` checkout. Follow `PiAgent/AGENTS.md` if Pi source is changed.
- Use the user's selected output directory for generated games; otherwise use `game/` under Pi's current directory. Godot verification results remain in the Pi session. Do not edit shared `assets/` or `Godot_Engine/` while generating a game.
- The original `../GameEva/` repository is a migration reference. Do not rewrite its history or delete it as part of this workspace cleanup.
- Commit each completed workspace change by default with a descriptive message. Stage only files related to that change.
