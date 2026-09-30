# A Pi Extension for Godot Game Development

Technical report | Implementation and local evidence as of 30 September 2026

## Abstract

The LTGD Agent System accepts a natural-language game request in a Pi conversation and lets Pi's native coding agent build a Godot project. A TypeScript extension takes over when the Generator ends its turn: it checks the declared project with Godot, then asks a separate short-context model call to review the original request against the project files. A confirmed engine failure or missing requirement triggers a narrowly scoped Planner response and another Generator turn. The task reaches `done` only after a current Godot pass and a positive requirement review. Twelve repository tests passed in this review, and five of six archived game directories passed a fresh Godot import and headless startup check; the sixth lacked `project.godot`. These checks establish technical behavior of the extension and snapshots, not the playability or quality of the games. Archived usage logs illustrate possible measurement fields but do not support a causal efficiency claim for the current implementation.

## 1 Problem and Scope

A generated Godot game consists of a configuration file, scenes, scripts, and often assets. A plausible answer in chat does not establish that the project imports, starts, or implements the requested player flow. LTGD places an automatic check at the end of a Pi coding turn while keeping the user's natural-language request in Pi as the only task entry point. The extension is under `LTGDAgentSystem/godot-pat/`; `LTGDAgentSystem/start.cmd` loads it through the installed `pi` command. No local Pi source checkout is required for normal use.

The default output directory is `game/` below Pi's current directory. A user can choose another directory. The Generator ends its turn with an exact `<ltgd-project-path>...</ltgd-project-path>` handoff, and the Executor checks that directory rather than guessing a path from the request. Shared `assets/` and `Godot_Engine/` are inputs and are excluded as project roots.

## 2 Method and Architecture

![Figure 1. Runtime boundaries and evidence flow](figures/ltgd_architecture_2026-09-30.png)

Pi owns the conversation, model session, and ordinary file-editing tools. The extension supplies task state, project inspection tools, the end-of-turn hook, and the `godot-status` command. It persists task state in Pi session entries. `project.ts` indexes scenes and scripts, extracts a main scene from `project.godot`, and hashes non-cache project files. The fingerprint ties a later requirement review to the files that passed Godot.

The Generator implements the original request directly. It is instructed to finish a focused first pass and give the actual output path. On `agent_before_settle`, the Executor binds that path, requires `project.godot`, and runs three ordered checks in `godot.ts`: structural presence of a scene and main scene, Godot editor import, and a 60-frame headless startup. Import is limited to 60 seconds and startup to 25 seconds. The current implementation runs Godot against the selected directory; it does not create an isolated verifier copy. Engine diagnostics are deduplicated, while the known shutdown resource message is treated as a warning.

After a Godot pass, the Executor issues a separate model request. It supplies the original goal, referenced task files, output directory, project index, and current text files. The reviewer returns one JSON status, `implemented` or `missing`, with evidence. The review rejects optional polish as a reason to continue and has a 240,000-character text limit. It also checks that the project fingerprint has not changed during review. This review is model-based source inspection, not a recorded playtest.

![Figure 2. Failure-triggered control flow](figures/ltgd_control_flow_2026-09-30.png)

Any confirmed Godot failure or concrete missing requirement moves the task to `plan`. The Planner receives the latest failure and relevant current source excerpts, then returns either `revise` with focused repair steps or `cannot_resolve_in_project` with a reason and evidence. The Planner cannot edit files. Pi resumes as Generator for the repair; the Executor checks the project again at the next turn boundary. If a repair changes no project file, the extension stops instead of repeating the same check. Infrastructure failures, missing path handoffs, invalid project roots, oversized review input, and model-call failures also stop with a reason. A passing Godot check followed by an `implemented` review records `done`.

## 3 Evaluation Procedure

This report uses two kinds of local evidence. First, the repository test file exercises controller transitions, path handoff, Planner and reviewer inputs, state restoration, real Godot import and startup, and CMD launcher loading. It was run with Node 24.19.0, the installed Pi package dependencies, and the local Godot 4.6.2 Windows console executable. Second, each archived game under `output/game/` was copied to a temporary directory without `.godot` cache data and passed through the current `verifyProject` function. This copy isolates the report's recheck from the archived project; it is a procedure used for this report, not a feature of the extension.

The archived usage exports in `output/token_usage/` are a separate historical observation. They use the provider-reported totals from one Pi session per condition. The sessions predate the latest path-handoff implementation and were not randomized or replicated. Their Token totals include repeatedly sent and cached context. Reasoning tokens are a subset of output tokens and are not added again.

## 4 Results

| Check | Observation | Evidence boundary |
| --- | --- | --- |
| Repository tests | 12 passed, 0 failed | Includes mocked model decisions and one real Godot smoke test; no gameplay score. |
| Archived project recheck | HSL direct, HSL LTGD, MAG LTGD, PIB direct, and PIB LTGD passed import and headless startup | Fresh check of copied snapshots on 30 September 2026. |
| MAG direct snapshot | `project.godot` absent at `output/game/MAG_direct` | No valid Godot project root was available for that snapshot. |

The five passing projects produced no blocking Godot diagnostic in this recheck. This says the engine could import and start their main scenes for the bounded check. It does not show that menus, controls, win conditions, visuals, or audio met their respective task instructions.

| Game | Run | Calls | Total Tokens | Output Tokens | Cost USD |
| --- | --- | ---: | ---: | ---: | ---: |
| Horror Signal Lost | Direct | 171 | 32,891,257 | 242,006 | 0.512166 |
| Horror Signal Lost | LTGD | 123 | 16,404,990 | 153,278 | 0.298924 |
| Puzzle Magnet Lab | Direct | 174 | 34,650,322 | 239,879 | 0.518349 |
| Puzzle Magnet Lab | LTGD | 138 | 19,465,906 | 188,248 | 0.357621 |
| Ivory Beats | Direct | 73 | 8,268,231 | 129,873 | 0.220367 |
| Ivory Beats | LTGD | 53 | 5,121,436 | 101,126 | 0.163108 |

The six rows come from `output/token_usage/{HSL,MAG,PIB}_{direct,LTGD}/usage.json`; all sessions used `deepseek-flash`. Total Tokens include uncached input, cache read, cache write, and output; reasoning tokens are already included in output. The archived LTGD sessions have lower logged totals in all three task pairs. The logs do not establish why: each condition has one run, the sessions used an earlier controller revision, and gameplay acceptance was not measured by a common evaluator. These numbers are descriptive records, not results for the current extension version.

## 5 Limitations

Godot import and a 60-frame headless run are narrow technical checks. They may miss input handling, later scene transitions, presentation faults, and features that require interaction. The separate reviewer reads source and task text but cannot see the rendered game or reliably prove the player experience. A positive review can therefore overstate completeness.

The Generator's explicit path handoff is a useful contract but also a failure point: a missing or wrong tag stops the task, and the extension does not search for a likely alternative. Project hashing excludes cache directories and symbolic links; it detects ordinary project-file changes, but it is not a full artifact provenance system. The 240,000-character review limit stops large projects rather than silently reviewing a partial source set.

The current `start.cmd` and tests target Windows and a local Godot 4.6.2 console executable. The available archived game outputs and usage sessions are development artifacts, not a controlled benchmark. No repeated trials, blinded playtesting, or common visual assessment were available. Token cost and completion quality cannot be attributed to the extension from those artifacts.

## 6 Conclusion

The implemented system makes the handoff from Pi coding to Godot checks automatic and gives confirmed failures a scoped repair loop. Local tests support the controller and launcher behavior; five archived project snapshots passed the current engine smoke check. A credible efficiency or game-quality result needs repeated runs from frozen task inputs and an independent gameplay evaluator.

## Repository Evidence

| Item | Path and use |
| --- | --- |
| Extension lifecycle | `LTGDAgentSystem/godot-pat/index.ts` — hooks, path handoff, automatic Executor and Planner calls. |
| State transitions | `LTGDAgentSystem/godot-pat/controller.ts` — generate, plan, review, done, stopped. |
| Engine checks | `LTGDAgentSystem/godot-pat/godot.ts` — structure, import, startup, diagnostics. |
| Requirement review | `LTGDAgentSystem/godot-pat/executor.ts` — source and task-file input, JSON review. |
| Repair planning | `LTGDAgentSystem/godot-pat/planner.ts` — focused failure input and repair schema. |
| Tests | `LTGDAgentSystem/tests/godot-pat.test.ts` — twelve checks run for this report. |
| Archived outputs | `output/game/` and `output/token_usage/` — exploratory snapshots and session exports. |
