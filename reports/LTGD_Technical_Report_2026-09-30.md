# A Pi Extension for Godot Game Development

Technical report | Implementation and local evidence as of 30 September 2026

## Abstract

The LTGD Agent System accepts a natural-language game request in a Pi conversation and divides the work among three roles. The Generator writes the Godot project, the Executor runs Godot and reviews the original requirement, and the Planner proposes a focused repair only after a confirmed failure. This division makes verification automatic at the end of a Generator turn and permits `done` only after a current Godot pass and positive requirement review. Twelve repository tests passed, and five of six archived game directories passed a fresh Godot import and headless startup check; the sixth lacked `project.godot`. In three archived one-run task pairs, LTGD logged 38.1% to 50.1% fewer Total Tokens than direct Pi runs. Those sessions used an earlier revision and lack a common gameplay assessment, so the observed differences do not establish a causal efficiency or quality gain for the current implementation.

## 1 Problem and Scope

A generated Godot game consists of a configuration file, scenes, scripts, and often assets. A plausible answer in chat does not establish that the project imports, starts, or implements the requested player flow. LTGD places an automatic check at the end of a Pi coding turn while keeping the user's natural-language request in Pi as the only task entry point. The extension is under `LTGDAgentSystem/godot-pat/`; `LTGDAgentSystem/start.cmd` loads it through the installed `pi` command. No local Pi source checkout is required for normal use.

The default output directory is `game/` below Pi's current directory. A user can choose another directory. The Generator ends its turn with an exact `<ltgd-project-path>...</ltgd-project-path>` handoff, and the Executor checks that directory rather than guessing a path from the request. Shared `assets/` and `Godot_Engine/` are inputs and are excluded as project roots.

## 2 Method and Architecture

![Figure 1. Runtime boundaries and evidence flow](figures/ltgd_architecture_2026-09-30.png)

Pi owns the conversation, model session, and ordinary file-editing tools. The extension supplies task state, project inspection tools, the end-of-turn hook, and the `godot-status` command. It persists task state in Pi session entries. `project.ts` indexes scenes and scripts, extracts a main scene from `project.godot`, and hashes non-cache project files. The fingerprint ties a later requirement review to the files that passed Godot.

The Generator implements the original request directly. It is instructed to finish a focused first pass and give the actual output path. On `agent_before_settle`, the Executor binds that path, requires `project.godot`, and runs three ordered checks in `godot.ts`: structural presence of a scene and main scene, Godot editor import, and a 60-frame headless startup. Import is limited to 60 seconds and startup to 25 seconds. The current implementation runs Godot against the selected directory; it does not create an isolated verifier copy. Engine diagnostics are deduplicated, while the known shutdown resource message is treated as a warning.

After a Godot pass, the Executor issues a separate model request. It supplies the original goal, referenced task files, output directory, project index, and current text files. The reviewer returns one JSON status, `implemented` or `missing`, with evidence. The review rejects optional polish as a reason to continue and has a 240,000-character text limit. It also checks that the project fingerprint has not changed during review. This review is model-based source inspection, not a recorded playtest.

![Figure 2. Failure-triggered control flow](figures/ltgd_control_flow_2026-09-30.png)

### 2.1 Responsibility and handoff

| Role | Trigger and input | Action and output |
| --- | --- | --- |
| Generator | The user's Pi request, or Planner repair steps after a failed check. | Uses Pi's normal coding tools to build the selected Godot project. It ends its turn with the actual project path; on a repair turn it is instructed to change only the confirmed failure. |
| Executor | Pi's `agent_before_settle` hook after the Generator completes a turn. | Binds the handed-off path, checks structure, imports and starts the game, then makes a separate requirement-review model call. It records the result and routes the task to review, plan, done, or stopped. |
| Planner | A failed Godot check or a reviewer finding of a concrete missing requirement. | Reads the original goal and latest failure. Engine failures include relevant code excerpts; requirement failures include missing-behavior evidence and a project overview. It returns JSON repair steps or a supported stop decision and does not edit files. |

The controller in `controller.ts` enforces the handoff: Godot `pass` leads to `review`, while `fail` leads to `plan`; a review of `implemented` leads to `done`, while `missing` leads back to `plan`. `index.ts` returns accepted repair steps to the Generator and automatically invokes the Executor after the next turn. If a repair leaves the project fingerprint unchanged, the extension stops rather than repeating the same check. Infrastructure failures, missing path handoffs, invalid project roots, oversized review input, and model-call failures also stop with a reason.

### 2.2 Example trace and intended effect

The repository's integration test supplies a concrete trace with mocked model decisions. An absent main scene fails Godot, so the Planner requests a scene repair. After the scene is added, Godot passes, but the reviewer reports that the requested scanning interaction is missing. The Planner then requests that specific repair; the Generator adds `Game.gd`, and a subsequent Godot pass plus `implemented` review reaches `done`. This test establishes the state transitions, not that a playable scanning game was produced.

The design is intended to spend the Generator's time on implementation, let the Executor decide whether another turn is warranted, and give the Planner only evidence from the latest failure rather than the Generator's full conversation. A direct pass avoids a Planner call. The automatic hook prevents a completed Generator turn from skipping checks, while the requirement review prevents a mere engine startup from ending the task. These are mechanisms visible in the code; their effect on real game quality and Token use requires separate evidence.

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

### 4.1 Archived session usage

| Game | Run | Calls | Total Tokens | Output Tokens | Cost USD |
| --- | --- | ---: | ---: | ---: | ---: |
| Horror Signal Lost | Direct | 171 | 32,891,257 | 242,006 | 0.512166 |
| Horror Signal Lost | LTGD | 123 | 16,404,990 | 153,278 | 0.298924 |
| Puzzle Magnet Lab | Direct | 174 | 34,650,322 | 239,879 | 0.518349 |
| Puzzle Magnet Lab | LTGD | 138 | 19,465,906 | 188,248 | 0.357621 |
| Ivory Beats | Direct | 73 | 8,268,231 | 129,873 | 0.220367 |
| Ivory Beats | LTGD | 53 | 5,121,436 | 101,126 | 0.163108 |

The six rows come from `output/token_usage/{HSL,MAG,PIB}_{direct,LTGD}/usage.json`; all sessions used `deepseek-flash`. Total Tokens include uncached input, cache read, cache write, and output; reasoning tokens are already included in output. Relative to the direct run of the same task, LTGD logged 50.1% fewer Total Tokens for Horror Signal Lost, 43.8% for Puzzle Magnet Lab, and 38.1% for Ivory Beats. The corresponding estimated costs were 41.6%, 31.0%, and 26.0% lower. This pattern is consistent with the intended shorter repair loop, but the logs do not identify the cause: each condition has one run, the sessions used an earlier controller revision, and gameplay acceptance was not measured by a common evaluator. These are descriptive comparisons, not measured effects of the current extension.

## 5 Limitations

Godot import and a 60-frame headless run are narrow technical checks. They may miss input handling, later scene transitions, presentation faults, and features that require interaction. The separate reviewer reads source and task text but cannot see the rendered game or reliably prove the player experience. A positive review can therefore overstate completeness.

The Generator's explicit path handoff is a useful contract but also a failure point: a missing or wrong tag stops the task, and the extension does not search for a likely alternative. Project hashing excludes cache directories and symbolic links; it detects ordinary project-file changes, but it is not a full artifact provenance system. The 240,000-character review limit stops large projects rather than silently reviewing a partial source set.

The current `start.cmd` and tests target Windows and a local Godot 4.6.2 console executable. The available archived game outputs and usage sessions are development artifacts, not a controlled benchmark. No repeated trials, blinded playtesting, or common visual assessment were available. Token cost and completion quality cannot be attributed to the extension from those artifacts.

## 6 Conclusion

LTGD's implemented result is a controlled division of labor: the Generator builds and repairs, the Executor checks the declared artifact and original requirement, and the Planner intervenes only after an observed failure. The automatic handoff and state transitions are supported by 12 passing tests; five archived project snapshots also passed the current engine smoke check. Across three historical task pairs, LTGD sessions logged 38.1% to 50.1% fewer Total Tokens and 26.0% to 41.6% lower estimated cost than direct sessions. This is a consistent descriptive pattern, but the one-run, earlier-revision records cannot establish that the current controller caused it. The strongest supported conclusion is that LTGD implements and exercises a failure-triggered verification and repair workflow; whether it improves completed gameplay or reproducibly reduces cost remains unmeasured.

Source basis: `LTGDAgentSystem/godot-pat/{index,controller,godot,executor,planner,project}.ts`, `LTGDAgentSystem/tests/godot-pat.test.ts`, `output/game/`, and `output/token_usage/`.
