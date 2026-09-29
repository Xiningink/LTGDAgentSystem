import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { parseContractItems } from "../godot-pat/contract.ts";
import { acceptPlan, activeWorkset, authorizeProposal, finishTask, generatorHandoff, migrateTaskState, newTask, recordCompletedWorkset, recordVerification, validatePlanScope, validateWorksetChecks, type DecompositionPlan, type TaskState, type Verification } from "../godot-pat/controller.ts";
import { classifyGodotDiagnostics, parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
import godotPat from "../godot-pat/index.ts";
import { parsePlannerOutput, plannerInput } from "../godot-pat/planner.ts";
import { inspectProject, inspectScene } from "../godot-pat/project.ts";
import { parsePlanScopeDecisions, parseScopeDecision } from "../godot-pat/scope.ts";

const godot = path.resolve(import.meta.dirname, "../../Godot_Engine/Godot_v4.6.2-stable_win64_console.exe");

test("scope suggestions cannot create work or reopen a completed requirement", () => {
	const state = newTask("Build a menu", [{ id: "R1", text: "A working menu", doneWhen: "Menu starts the game" }]);
	const proposal = { basis: "user_requirement" as const, sourceId: "R1", expected: "Menu starts the game",
		observed: "The menu starts, but another color might look nicer", evidence: "Current menu works", proposedGoal: "Change the menu color" };
	const optional = authorizeProposal(state, proposal, "optional", "The menu requirement is met.");
	assert.deepEqual(activeWorkset(optional), activeWorkset(state));
	assert.equal(optional.suggestions?.length, 1);
	const uncertain = authorizeProposal(optional, proposal, "uncertain", "No failure is demonstrated.");
	assert.deepEqual(activeWorkset(uncertain), activeWorkset(state));
	const required = authorizeProposal(state, { ...proposal, observed: "The menu button does not start the game", proposedGoal: "Connect the start button" },
		"required", "R1 is not met.");
	assert.equal(activeWorkset(required).items.at(-1)?.id, "W1");
	assert.equal(required.workItems.at(-1)?.sourceId, "R1");
	const closed = { ...state, workItems: state.workItems.map((item) => ({ ...item, status: "closed" as const })) };
	assert.throws(() => authorizeProposal(closed, proposal, "required", "Try again"), /cannot be reopened/);
	assert.equal(parseScopeDecision('{"decision":"optional","reason":"Already works"}').decision, "optional");
});

test("review gaps remain missing when the proposed fix is optional or uncertain", () => {
	const reviewed = recordVerification(newTask("Build a menu", [{ id: "R1", text: "Start button works" }]),
		{ status: "pass", stage: "runtime", errors: [], score: 10, fingerprint: "current" });
	const check = { id: "R1", status: "missing" as const, expected: "Start button works", observed: "Button does nothing", evidence: "No start handler" };
	assert.throws(() => finishTask(reviewed, [check], "current", {}), /Missing scope decision/);
	const optional = finishTask(reviewed, [check], "current", { R1: "optional" });
	assert.equal(optional.phase, "stopped");
	assert.equal((optional.completionEvidence?.[0] as { status: string })?.status, "missing");
	assert.match(optional.plannerError ?? "", /remains reported missing/);
	const uncertain = finishTask(reviewed, [check], "current", { R1: "uncertain" });
	assert.equal(uncertain.phase, "stopped");
	assert.equal((uncertain.completionEvidence?.[0] as { status: string })?.status, "missing");
	assert.match(uncertain.plannerError ?? "", /manual review/);
	const required = finishTask(reviewed, [check], "current", { R1: "required" });
	assert.equal(required.phase, "generate");
	assert.deepEqual(required.pendingRequirements, ["R1"]);
	assert.equal(required.workItems.at(-1)?.source, "requirement_gap");
});

test("Planner children must cite authorized parents and optional children are rejected", () => {
	const failure = recordVerification(newTask("Build a menu"), { status: "fail", stage: "import",
		errors: [{ stage: "import", message: "Scene parse error" }], score: 0, fingerprint: "a" });
	const plan: DecompositionPlan = { decision: "revise", reason: "Fix parse error", objective: "Import scene",
		subtasks: [{ id: "S1", parentWorkItemId: "E1-1", problem: "Parse error", goal: "Fix scene" }] };
	assert.doesNotThrow(() => validatePlanScope(failure, plan));
	assert.throws(() => validatePlanScope(failure, { ...plan, subtasks: [{ ...plan.subtasks![0], parentWorkItemId: "R1" }] }), /authorized work item/);
	const decisions = parsePlanScopeDecisions('{"decisions":[{"id":"S1","decision":"optional","reason":"Decorative change"}]}', ["S1"]);
	assert.equal(decisions.S1, "optional");
	assert.throws(() => parsePlanScopeDecisions('{"decisions":[]}', ["S1"]), /every subtask/);
	const decomposed = acceptPlan(failure, plan);
	assert.deepEqual(activeWorkset(decomposed).items.map((item) => item.id), ["S1"]);
});

test("older session plans without a traceable parent do not become completed work", () => {
	const migrated = migrateTaskState({ goal: "Build a menu", schemaVersion: 4, phase: "generate", plan: [{ id: "S1", problem: "Old task", goal: "Unknown origin" }] });
	assert.equal(migrated.schemaVersion, 6);
	assert.equal(migrated.phase, "stopped");
	assert.match(migrated.plannerError ?? "", /no traceable work source/);
});

test("Planner input requires an actual failed verification", async () => {
	const project = { project: os.tmpdir(), mainScene: undefined, scenes: [], scripts: [], resources: 0, fingerprint: "x" };
	await assert.rejects(() => plannerInput(newTask("Build a menu"), project), /recorded failed Godot verification/);
	const passed = recordVerification(newTask("Build a menu"), { status: "pass", stage: "runtime", errors: [], score: 10, fingerprint: "x" });
	await assert.rejects(() => plannerInput(passed, project), /recorded failed Godot verification/);
});

test("Generator proposals need a scope verdict before joining the workset", async () => {
	const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
	const tools = new Map<string, unknown>();
	const entries: TaskState[] = [];
	const saved = { ...newTask("Build a menu", [{ id: "R1", text: "Start button works" }]), projectPath: os.tmpdir() };
	godotPat({
		on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
		registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {},
		appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
	} as unknown as ExtensionAPI);
	const ctx = { cwd: os.tmpdir(), model: { provider: "test", id: "mock" }, thinkingLevel: "off",
		modelRegistry: { streamSimple(_model: unknown, request: { messages: { content: { text: string }[] }[] }) {
			const proposal = JSON.parse(request.messages[0].content[0].text).proposal;
			const decision = proposal.proposedGoal.includes("color") ? "optional" : "required";
			return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify({ decision, reason: "Reviewed against R1" }) }] }) };
		} },
		sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] } };
	await handlers.get("session_start")?.({}, ctx);
	assert.equal(tools.has("godot_decompose_work"), false, "Generator must not have a Planner entry point");
	type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
	const propose = tools.get("godot_propose_work") as TestTool;
	const base = { basis: "user_requirement", sourceId: "R1", expected: "Start button works", observed: "Button works", evidence: "Click opens game" };
	const optional = await propose.execute("optional", { ...base, proposedGoal: "Change color" }, undefined, undefined, ctx);
	assert.match(optional.content[0].text, /suggestion only/);
	assert.equal(entries.at(-1)?.extraWorkIds?.length ?? 0, 0);
	await propose.execute("required", { ...base, observed: "Button does nothing", proposedGoal: "Connect start button" }, undefined, undefined, ctx);
	assert.deepEqual(entries.at(-1)?.extraWorkIds, ["W1"]);
	assert.equal(activeWorkset(entries.at(-1)!).items.at(-1)?.goal, "Connect start button");
});

test("Controller audits instruction.md before locking the requirement contract", async () => {
	const cwd = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-contract-"));
	try {
		await fs.writeFile(path.join(cwd, "instruction.md"), "Radio scanning\nJamming\nAudio cues\n");
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		godotPat({ on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); } } as unknown as ExtensionAPI);
		const ctx = { cwd, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string; messages: { content: { text: string }[] }[] }) {
				const sources = JSON.parse(request.messages[0].content[0].text).sources as { id: string; text: string }[];
				const sourceId = sources.find((source) => source.id.startsWith("file:"))?.id;
				assert.ok(sourceId, "Controller must read instruction.md itself");
				const item = (text: string) => ({ text, doneWhen: `${text} works`, sourceEvidence: [{ sourceId, quote: text }] });
				const result = request.systemPrompt.includes("Audit an LTGD")
					? { missing: [item("Jamming"), item("Audio cues")], uncertain: false }
					: { requirements: [item("Radio scanning")] };
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(result) }] }) };
			} }, sessionManager: { getBranch: () => [] } };
		await handlers.get("session_start")?.({}, ctx);
		await handlers.get("input")?.({ source: "user", text: "Build the game in instruction.md" }, ctx);
		type TestTool = { execute: (id: string, params: object, signal: undefined, update: undefined, context: object) => Promise<unknown> };
		await (tools.get("godot_set_project") as TestTool).execute("select", { requirements: [{ id: "R1", text: "Radio scanning" }] }, undefined, undefined, ctx);
		const locked = entries.at(-1)!;
		assert.deepEqual(locked.requirements.map((item) => item.text), ["Radio scanning", "Jamming", "Audio cues"]);
		assert.equal(locked.requirements[2].sourceEvidence?.[0].quote, "Audio cues");
		assert.equal(locked.requirementSources?.length, 2);
		assert.equal(locked.schemaVersion, 6);
		const tampered = migrateTaskState({ ...locked, requirements: locked.requirements.slice(0, 1) });
		assert.equal(tampered.phase, "stopped", "a locked requirement must not disappear during restore");
		assert.match(tampered.plannerError ?? "", /contract changed/);
		assert.equal(migrateTaskState({ ...locked, goal: "Different game" }).phase, "stopped");
		const invalidEvidence = migrateTaskState({ ...locked, requirements: locked.requirements.map((item, index) => index
			? item : { ...item, sourceEvidence: [{ sourceId: "user_request", quote: "not in the request" }] }) });
		assert.equal(invalidEvidence.phase, "stopped");
		assert.throws(() => parseContractItems(JSON.stringify({ requirements: [{ text: "Invented feature", doneWhen: "It works",
			sourceEvidence: [{ sourceId: "user_request", quote: "not in the request" }] }] }), "requirements", locked.requirementSources!), /match a supplied source/);
	} finally {
		if (!cwd.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(cwd, { recursive: true, force: true });
	}
});

test("Planner cannot turn an import error into optional redesign work", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-plan-scope-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		const saved = { ...recordVerification(newTask("Build a game"), { status: "fail" as const, stage: "import",
			errors: [{ stage: "import", message: "Main.tscn parse error" }], score: 0, fingerprint: "before" }), projectPath: root };
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		godotPat({ on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); } } as unknown as ExtensionAPI);
		const ctx = { cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string }) {
				const result = request.systemPrompt.includes("plan scope reviewer")
					? { decisions: [{ id: "S1", decision: "required", reason: "Fixes the parse error" }, { id: "S2", decision: "optional", reason: "Menu redesign is unrelated" }] }
					: { decision: "revise", reason: "Fix import", objective: "Import project", subtasks: [
						{ id: "S1", parentWorkItemId: "E1-1", problem: "Parse error", goal: "Fix Main.tscn" },
						{ id: "S2", parentWorkItemId: "E1-1", problem: "Menu colors", goal: "Redesign menu" },
					] };
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(result) }] }) };
			} }, sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] } };
		await handlers.get("session_start")?.({}, ctx);
		type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
		const result = await (tools.get("godot_verify") as TestTool).execute("resume", {}, undefined, undefined, ctx);
		assert.equal(entries.at(-1)?.phase, "stopped");
		assert.match(result.content[0].text, /unsupported work/);
		assert.equal(entries.at(-1)?.plan.length, 0);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("project selection creates game/ only for an unspecified output path", async () => {
	const cwd = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-project-selection-"));
	try {
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: unknown[] = [];
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); },
			registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data); },
		} as unknown as ExtensionAPI);
		const ctx = { cwd, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string; messages: { content: { text: string }[] }[] }) {
				const sources = JSON.parse(request.messages[0].content[0].text).sources as { id: string; text: string }[];
				const prompt = sources[0].text;
				const requirements = prompt.includes("Start menu")
					? ["Start menu", "Signal collection"].map((text) => ({ text, doneWhen: `${text} works`, sourceEvidence: [{ sourceId: "user_request", quote: text }] }))
					: [{ text: prompt, doneWhen: "Game starts", sourceEvidence: [{ sourceId: "user_request", quote: prompt }] }];
				const result = request.systemPrompt.includes("Audit an LTGD") ? { missing: [], uncertain: false } : { requirements };
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(result) }] }) };
			} }, sessionManager: { getBranch: () => [] } };
		await handlers.get("session_start")?.({}, ctx);
		assert.equal(handlers.has("tool_call"), true, "LTGD installs a phase-aware tool gate");
		assert.equal(await handlers.get("tool_call")?.({ toolName: "bash", input: { command: "pwd" } }, ctx), undefined, "unrelated Pi tools remain available before a game is selected");
		assert.equal(handlers.has("agent_end"), false, "unrelated turns must not trigger automatic Godot verification");
		const unrelated = await handlers.get("before_agent_start")?.({ prompt: "List my notes", systemPrompt: "BASE" }, ctx) as { systemPrompt: string };
		assert.match(unrelated.systemPrompt, /For other tasks, leave LTGD tools unused/);
		assert.equal(entries.length, 0, "an unrelated request must not start a Godot task");
		await handlers.get("input")?.({ source: "user", text: "Build in output/AS/HorrorSignalLost with Start menu and Signal collection" }, ctx);
		type TestTool = { execute: (id: string, params: object, signal: undefined, update: undefined, context: object) => Promise<{ content: { text: string }[] }> };
		const select = tools.get("godot_set_project") as TestTool;
		const inspect = tools.get("godot_inspect_project") as TestTool;
		assert.ok(select && inspect);
		const explicit = path.join(cwd, "output", "AS", "HorrorSignalLost");
		await select.execute("select", { project: "output/AS/HorrorSignalLost", requirements: [{ id: "R1", text: "Start menu" }, { id: "R2", text: "Signal collection" }] }, undefined, undefined, ctx);
		assert.equal((entries.at(-1) as { projectPath: string }).projectPath, explicit);
		assert.deepEqual((entries.at(-1) as TaskState).requirements.map((item) => item.id), ["R1", "R2"]);
		await select.execute("repeat-select", { requirements: [{ id: "R3", text: "Optional feature" }] }, undefined, undefined, ctx);
		assert.deepEqual((entries.at(-1) as TaskState).requirements.map((item) => item.id), ["R1", "R2"], "a repeated selection must not replace the active workset");
		await assert.rejects(() => select.execute("premature-new-task", { new_task: true }, undefined, undefined, ctx), /new user request/);
		assert.equal(await fs.stat(explicit).then((item) => item.isDirectory()), true);
		assert.equal(await fs.stat(path.join(cwd, "game")).then(() => true, () => false), false);
		await fs.writeFile(path.join(explicit, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		await fs.writeFile(path.join(explicit, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const inspected = await inspect.execute("inspect", {}, undefined, undefined, ctx);
		assert.equal(JSON.parse(inspected.content[0].text).mainScene, "res://Main.tscn");
		await handlers.get("input")?.({ source: "user", text: "Start a new game without an output path" }, ctx);
		await select.execute("select", { new_task: true }, undefined, undefined, ctx);
		assert.equal((entries.at(-1) as { projectPath: string }).projectPath, path.join(cwd, "game"));
		assert.deepEqual((entries.at(-1) as TaskState).requirements.map((item) => item.text), ["Start a new game without an output path"]);
		assert.equal(await fs.stat(path.join(cwd, "game")).then((item) => item.isDirectory()), true);
		assert.equal(ctx.cwd, cwd);
	} finally {
		if (!cwd.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(cwd, { recursive: true, force: true });
	}
});

test("first failed verification plans immediately; one full-plan pass enters review", () => {
	const failure: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "parse error" }], score: 0, fingerprint: "a" };
	const requirement = { id: "R1", text: "Build a game" };
	const plan = recordVerification(newTask("Build a game", [requirement]), failure);
	assert.equal(plan.phase, "plan");
	const decomposition: DecompositionPlan = {
		decision: "revise", reason: "The project cannot import",
		objective: "Make the main scene import and start",
		subtasks: [
			{ id: "S1", problem: "Scene import fails", goal: "Fix scene", suggested_files: ["Main.tscn"] },
			{ id: "S2", problem: "Route is not connected", goal: "Wire game route", suggested_files: ["Route.gd"] },
		],
	};
	const executing = acceptPlan(plan, decomposition);
	assert.equal(executing.phase, "generate");
	assert.deepEqual(activeWorkset(executing), { source: "planner", items: [{ id: "S1", goal: "Fix scene" }, { id: "S2", goal: "Wire game route" }] });
	assert.match(generatorHandoff(executing), /"problem":"Scene import fails"/);
	assert.match(generatorHandoff(executing), /"suggested_files":\["Route.gd"\]/);
	const completed = [{ id: "S1", status: "completed" as const, evidence: "Scene now imports" }, { id: "S2", status: "completed" as const, evidence: "Route connected" }];
	const progress = recordCompletedWorkset(executing, completed, "c");
	assert.equal(progress.solved[0].id, "S1");
	assert.equal(progress.solved[1].id, "S2");
	assert.throws(() => recordCompletedWorkset(executing, [{ id: "missing", status: "completed", evidence: "no" }], "c"));
	const reviewed = recordVerification(progress, { ...failure, status: "pass", score: 10, fingerprint: "c" });
	assert.equal(reviewed.phase, "review");
	assert.throws(() => finishTask(reviewed, [], "c"));
	const checks = [{ id: "R1", status: "implemented" as const, evidence: "Game scene created" }];
	assert.throws(() => finishTask(reviewed, checks, "stale"));
	assert.equal(finishTask(reviewed, checks, "c").phase, "done");
	assert.equal(recordVerification(plan, failure).phase, "stopped");
	const directReview = recordVerification(newTask("Build a game"), { ...failure, status: "pass", score: 10 });
	assert.equal(directReview.phase, "review");
	assert.equal(finishTask(directReview, checks, "a").phase, "done");
	assert.throws(() => acceptPlan(plan, { ...decomposition, subtasks: [{ ...decomposition.subtasks![0], problem: "" }] }));
	assert.equal(acceptPlan(plan, { ...decomposition, subtasks: [{ ...decomposition.subtasks![0], suggested_files: ["../outside.tscn"] }] }).phase, "generate");
	assert.equal(recordVerification(executing, { ...failure, fingerprint: "d" }).phase, "plan");
	let improving = executing;
	for (let remaining = 15; remaining >= 2; remaining--) {
		improving = recordVerification(improving, { ...failure, fingerprint: `revision-${remaining}`, errors: Array.from({ length: remaining }, (_, index) => ({ stage: "import", message: `error ${index}` })) });
		assert.equal(improving.phase, "plan");
		improving = acceptPlan(improving, decomposition);
	}
});

test("review checks fixed requirements and sends only missing work back to generation", () => {
	const requirements = [{ id: "R1", text: "Start menu" }, { id: "R2", text: "Signal collection" }];
	assert.throws(() => newTask("Game", [{ id: "R1", text: "Menu" }, { id: "R1", text: "Duplicate" }]), /unique/);
	assert.deepEqual(activeWorkset(newTask("Game", requirements)), { source: "user", items: [{ id: "R1", goal: "Start menu" }, { id: "R2", goal: "Signal collection" }] });
	const reviewed = recordVerification(newTask("Game", requirements), { status: "pass", stage: "runtime", errors: [], score: 10, fingerprint: "current" });
	assert.throws(() => finishTask(reviewed, [{ id: "R1", status: "implemented", evidence: "Menu scene" }], "current"), /every original requirement/);
	assert.throws(() => finishTask(reviewed, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R1", status: "implemented", evidence: "Duplicate" },
	], "current"), /each original ID/);
	const missing = finishTask(reviewed, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R2", status: "missing", evidence: "No collection interaction" },
	], "current");
	assert.equal(missing.phase, "generate");
	assert.deepEqual(missing.pendingRequirements, ["R2"]);
	assert.deepEqual(activeWorkset(missing), { source: "review", items: [{ id: "R2", goal: "Signal collection" }] });
	assert.equal(missing.plan.length, 0);
	assert.throws(() => finishTask(missing, [], "current"), /successful full-project review/);
	const failedAfterGap = recordVerification(missing, { status: "fail", stage: "import", errors: [{ stage: "import", message: "parse error" }], score: 0, fingerprint: "changed" });
	const plannedAfterGap = acceptPlan(failedAfterGap, { decision: "revise", reason: "Import broke during the missing requirement", objective: "Restore import", subtasks: [{ id: "S1", problem: "Parse error", goal: "Import cleanly" }] });
	assert.equal(plannedAfterGap.pendingRequirements, undefined, "the Planner handoff should take priority after a failed repair");
	const done = finishTask(reviewed, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R2", status: "needs_playtest", evidence: "Collection code exists; timing needs manual playtest" },
	], "current");
	assert.equal(done.phase, "done");
	assert.deepEqual(done.completionEvidence?.[1], { id: "R2", status: "needs_playtest", evidence: "Collection code exists; timing needs manual playtest" });
});

test("workset reports require every active ID exactly once and keep unresolved work out of verification", () => {
	const state = newTask("Game", [{ id: "R1", text: "Menu" }, { id: "R2", text: "Movement" }]);
	const completed = { id: "R1", status: "completed" as const, evidence: "Menu created" };
	const unresolved = { id: "R2", status: "unresolved" as const, evidence: "Movement script is not connected" };
	assert.deepEqual(validateWorksetChecks(state, [completed, unresolved]).unresolved, [unresolved]);
	assert.throws(() => validateWorksetChecks(state, undefined), /workset_checks/);
	assert.throws(() => validateWorksetChecks(state, [completed]), /Missing: R2/);
	assert.throws(() => validateWorksetChecks(state, [completed, completed]), /Duplicate/);
	assert.throws(() => validateWorksetChecks(state, [completed, { ...unresolved, id: "R3" }]), /Unknown/);
	assert.throws(() => validateWorksetChecks(state, [completed, { ...unresolved, evidence: " " }]), /nonempty/);
	assert.throws(() => validateWorksetChecks(state, [completed, { ...unresolved, status: "unknown" as "unresolved" }]), /Invalid workset status/);
	assert.throws(() => recordCompletedWorkset(state, [completed, unresolved], "x"), /incomplete/);
	const reviewed = recordVerification(state, { status: "pass", stage: "runtime", errors: [], score: 10, fingerprint: "x" });
	assert.deepEqual(validateWorksetChecks(reviewed, [{ id: "R2", status: "completed", evidence: "Movement connected" }], "R2").workset, { source: "review", items: [{ id: "R2", goal: "Movement" }] });
	assert.throws(() => validateWorksetChecks(reviewed, [completed], "R3"), /Unknown original requirement/);
});

test("Planner may stop without code edits and repeated unchanged failures have a bounded path", () => {
	const failure: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "same error" }], score: 0, fingerprint: "a" };
	const first = recordVerification(newTask("Game"), failure);
	assert.throws(() => acceptPlan(first, { decision: "cannot_resolve_in_project", reason: "No code fix" }), /requires verification evidence/);
	const stopped = acceptPlan(first, { decision: "cannot_resolve_in_project", reason: "Evidence points outside project", evidence: ["Godot output shows a missing executable"] });
	assert.equal(stopped.phase, "stopped");
	assert.equal(stopped.plan.length, 0);
	assert.match(stopped.plannerError ?? "", /missing executable/);
	const revised = acceptPlan(first, { decision: "revise", reason: "Import error", objective: "Fix import", subtasks: [{ id: "S1", problem: "Parse error", goal: "Import cleanly" }] });
	const second = recordVerification(revised, { ...failure, fingerprint: "b" });
	assert.equal(second.phase, "plan");
	assert.equal(second.unchangedFailureStreak, 1);
	const third = recordVerification(acceptPlan(second, { decision: "revise", reason: "Still fails", objective: "Fix import", subtasks: [{ id: "S1", problem: "Parse error", goal: "Import cleanly" }] }), { ...failure, fingerprint: "c" });
	assert.equal(third.phase, "stopped");
	assert.equal(third.unchangedFailureStreak, 2);
	const improved = recordVerification(revised, { ...failure, fingerprint: "b", errors: [{ stage: "import", message: "different error" }] });
	assert.equal(improved.phase, "plan");
	assert.equal(improved.unchangedFailureStreak, 0);
});

test("Planner receives every verification error and nearby current code without reading outside the project", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-planner-input-"));
	try {
		const source = ["extends Node", "", "func play():", ...Array.from({ length: 45 }, (_, i) => `\tvar value_${i} = ${i}`)].join("\n");
		await fs.writeFile(path.join(root, "Player.gd"), source);
		const errors = Array.from({ length: 20 }, (_, index) => ({ stage: "import", file: "res://Player.gd", line: index + 15, message: `error ${index}: ${"x".repeat(500)}` }));
		errors.push({ stage: "import", file: "../outside.gd", line: 1, message: "outside" });
		const state = recordVerification(newTask("Build a game"), { status: "fail", stage: "import", errors, score: 0, fingerprint: "x" });
		const input = JSON.parse(await plannerInput(state, { project: root, mainScene: "res://Main.tscn", scenes: [], scripts: ["Player.gd"], resources: 2, fingerprint: "x" }));
		assert.equal(input.latest_failure.errors.length, 21);
		assert.equal(input.latest_failure.errors[19].message.length, 510);
		assert.equal(input.current_code.length, 1);
		assert.match(input.current_code[0].code, /func play\(\):/);
		assert.ok(input.code_unavailable.some((item: { file: string }) => item.file === "../outside.gd"));
		assert.deepEqual(input.completed_subtasks, []);
		assert.equal(parsePlannerOutput('```json\n{"decision":"revise","reason":"r","objective":"x","subtasks":[{"id":"S1","problem":"p","goal":"g"}]}\n```').objective, "x");
		assert.throws(() => parsePlannerOutput("not json"));
		assert.equal(recordVerification(newTask("Game"), { status: "infrastructure", stage: "godot", errors: [], score: 0, fingerprint: "x" }).phase, "generate");
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("Godot parsing keeps early, late, and long distinct errors", () => {
	const errors = Array.from({ length: 20 }, (_, index) => `ERROR: res://scripts/Player.gd:${index + 1} - failure ${index} ${"x".repeat(500)}`);
	const output = `${errors[0]}\n${"ordinary output\n".repeat(150_000)}${errors.slice(1).join("\n")}\n${errors[0]}\n`;
	assert.ok(output.length > 2_000_000);
	const parsed = parseGodotErrors(output, "import");
	assert.equal(parsed.length, 20);
	assert.equal(parsed[0].line, 1);
	assert.equal(parsed[19].line, 20);
	assert.ok(parsed[0].message.length > 400);
});

test("exit-time resource cleanup is reported without hiding actual Godot script errors", () => {
	const cleanup = "ERROR: 4 resources still in use at exit (run with --verbose for details).";
	const scriptError = "SCRIPT ERROR: Invalid call in res://Player.gd:25";
	const onlyCleanup = classifyGodotDiagnostics(parseGodotErrors(`${cleanup}\n`, "runtime"));
	assert.equal(onlyCleanup.blocking.length, 0);
	assert.equal(onlyCleanup.warnings[0].message, cleanup);
	const mixed = classifyGodotDiagnostics(parseGodotErrors(`${scriptError}\n${cleanup}\n`, "runtime"));
	assert.equal(mixed.blocking.length, 1);
	assert.match(mixed.blocking[0].message, /Invalid call/);
	assert.equal(mixed.warnings.length, 1);
	assert.equal(classifyGodotDiagnostics(parseGodotErrors("ERROR: Failed loading resource: res://missing.tres", "import")).blocking.length, 1);
});

test("godot_get_errors exposes the full in-session result without a report file", async () => {
	const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
	const tools = new Map<string, unknown>();
	const errors = Array.from({ length: 8 }, (_, index) => ({ stage: "import", message: `failure ${index}` }));
	const saved = recordVerification(newTask("Build a game"), { status: "fail", stage: "import", errors, score: 0, fingerprint: "x" });
	godotPat({
		on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
		registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {}, appendEntry() {},
	} as unknown as ExtensionAPI);
	const ctx = { cwd: os.tmpdir(), sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] } };
	await handlers.get("session_start")?.({}, ctx);
	const getErrors = tools.get("godot_get_errors") as { execute: () => Promise<{ content: { text: string }[] }> };
	const result = await getErrors.execute();
	assert.match(result.content[0].text, /failure 7/);
	assert.match(result.content[0].text, /8 distinct errors/);
});

test("legacy done without completion evidence resumes at review; versioned done stays done", async () => {
	const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
	const legacy = { ...newTask("Old game"), projectPath: os.tmpdir(), phase: "done", lastVerification: { status: "pass" }, schemaVersion: undefined };
	const current = { ...newTask("New game"), projectPath: os.tmpdir(), phase: "done", completionEvidence: ["checked"] };
	let saved: unknown = legacy;
	const entries: TaskState[] = [];
	godotPat({
		on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
		registerTool() {}, registerCommand() {}, appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
	} as unknown as ExtensionAPI);
	const ctx = { cwd: os.tmpdir(), sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] } };
	const system = { role: "system", content: "BASE", timestamp: Date.now() };
	await handlers.get("session_start")?.({}, ctx);
	const resumed = await handlers.get("context_with_system")?.({ messages: [system] }, ctx) as { messages: { sections: Record<string, string> }[] };
	assert.match(resumed.messages[0].sections["ltgd-current-state"], /Phase: review/);
	saved = current;
	await handlers.get("session_tree")?.({}, ctx);
	const fresh = await handlers.get("context_with_system")?.({ messages: [system] }, ctx);
	assert.equal(fresh, undefined, "completed Godot tasks must not affect later unrelated requests");
	assert.equal(entries.length, 0);
});

test("a malformed isolated Planner response gets one bounded retry", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-planner-retry-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		const failure: Verification = { status: "fail", stage: "structure", errors: [{ stage: "structure", message: "No scene" }], score: 0, fingerprint: "x" };
		const saved: TaskState = { ...recordVerification(newTask("Build a game"), failure), projectPath: root };
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		let calls = 0;
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {}, appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
		} as unknown as ExtensionAPI);
		const ctx = {
			cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string }) {
				calls++;
				const output = request.systemPrompt.includes("scope reviewer")
					? { decisions: [{ id: "S1", decision: "required", reason: "The scene is missing" }] }
					: calls === 1 ? "invalid" : {
						decision: "revise", reason: "Scene is missing", objective: "Create scene",
						subtasks: [{ id: "S1", parentWorkItemId: "E1-1", problem: "Scene is missing", goal: "Create scene", suggested_files: ["Main.tscn"] }],
					};
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: typeof output === "string" ? output : JSON.stringify(output) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		await handlers.get("before_agent_start")?.({ prompt: "List unrelated files", systemPrompt: "BASE" }, ctx);
		assert.equal(calls, 0, "unrelated requests must not resume a pending Planner automatically");
		type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
		const resumed = await (tools.get("godot_verify") as TestTool).execute("resume-plan", {}, undefined, undefined, ctx);
		assert.equal(calls, 3);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.match(resumed.content[0].text, /Generator plan/);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("a no-code-change Planner decision stops automatic edits without claiming verification passed", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-no-change-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		let calls = 0;
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {}, appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
		} as unknown as ExtensionAPI);
		const ctx = {
			cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple() {
				calls++;
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify({
					decision: "cannot_resolve_in_project", reason: "The supplied failure does not identify a project-code fix", evidence: ["The verifier returned no source location"],
				}) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: { ...newTask("Build a game"), projectPath: root } }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
		const verify = tools.get("godot_verify") as TestTool;
		const result = await verify.execute("verify", { workset_checks: [{ id: "R1", status: "completed", evidence: "Project files created" }] }, undefined, undefined, ctx);
		assert.equal(calls, 1);
		assert.match(result.content[0].text, /Stop automatic retries/);
		assert.doesNotMatch(result.content[0].text, /Generator plan/);
		assert.equal(entries.at(-1)?.phase, "stopped");
		assert.equal(entries.at(-1)?.lastVerification?.status, "fail");
		await assert.rejects(() => verify.execute("verify-again", {}, undefined, undefined, ctx), /task has ended/);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("failed verification calls a short-context Planner and hands its whole plan to Generator", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-plan-handoff-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		let plannerCalls = 0;
		let plannerRequest = "";
		const initial = { ...newTask("Build a complete game"), projectPath: root };
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); },
			registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
		} as unknown as ExtensionAPI);
		const ctx = {
			cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string; messages: { content: { text: string }[] }[] }, options: { reasoning?: string }) {
				if (request.systemPrompt.includes("scope reviewer")) return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: request.systemPrompt.includes("plan scope")
					? JSON.stringify({ decisions: [{ id: "S1", decision: "required", reason: "The scene error needs repair" }] })
					: JSON.stringify({ decision: "required", reason: "The original requirement is missing" }) }] }) };
				plannerCalls++;
				plannerRequest = request.messages[0].content[0].text;
				assert.equal(options.reasoning, undefined);
				const parent = JSON.parse(plannerRequest).authorized_work[0].id;
				const decomposition: DecompositionPlan = { decision: "revise", reason: "Main scene is missing", objective: "Make the game boot and navigate",
					subtasks: [{ id: "S1", parentWorkItemId: parent, problem: "Main scene is missing", goal: "Create main scene", suggested_files: ["Main.tscn"] }] };
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(decomposition) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: initial }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
		const tool = tools.get("godot_verify") as TestTool;
		const initialUnresolved = await tool.execute("verify-incomplete", { workset_checks: [{ id: "R1", status: "unresolved", evidence: "Main scene is not ready" }] }, undefined, undefined, ctx);
		assert.match(initialUnresolved.content[0].text, /Current user workset is incomplete/);
		assert.match(initialUnresolved.content[0].text, /Godot verification was not run/);
		assert.equal(plannerCalls, 0);
		assert.equal(entries.length, 0, "an unresolved report must not mutate task state");
		const result = await tool.execute("verify-fail", { workset_checks: [{ id: "R1", status: "completed", evidence: "Game files created" }] }, undefined, undefined, ctx);
		assert.equal(plannerCalls, 1);
		assert.equal("usage" in result, false);
		assert.deepEqual(Object.keys(JSON.parse(plannerRequest)), ["original_requirement", "authorized_work", "project_overview", "latest_failure", "current_code", "code_unavailable", "completed_subtasks"]);
		assert.match(result.content[0].text, /"problem":"Main scene is missing"/);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.equal(tools.has("godot_plan"), false);
		assert.equal(tools.has("godot_subtask_done"), false);
		const system = { role: "system", content: "BASE", timestamp: Date.now() };
		const phase = await handlers.get("context_with_system")?.({ messages: [system] }, ctx) as { messages: { sections: Record<string, string> }[] };
		assert.match(phase.messages[0].sections["ltgd-current-state"], /Authorized planner workset: S1: Create main scene/);
		assert.doesNotMatch(phase.messages[0].sections["ltgd-current-state"], /"problem"/);
		await assert.rejects(() => tool.execute("verify-no-report", {}, undefined, undefined, ctx), /workset_checks/);
		const planUnresolved = await tool.execute("verify-plan-incomplete", { workset_checks: [{ id: "S1", status: "unresolved", evidence: "Main scene syntax still fails" }] }, undefined, undefined, ctx);
		assert.match(planUnresolved.content[0].text, /Current planner workset is incomplete/);
		assert.equal(plannerCalls, 1);
		assert.equal(entries.at(-1)?.attempts, 1);
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"\n');
		await handlers.get("agent_end")?.({}, ctx);
		assert.equal(plannerCalls, 1, "plan execution must not auto-verify at agent_end");
		const secondFailure = await tool.execute("verify-fail-again", { workset_checks: [{ id: "S1", status: "completed", evidence: "Main scene revised" }] }, undefined, undefined, ctx);
		assert.match(secondFailure.content[0].text, /Godot FAIL/);
		assert.equal(plannerCalls, 2);
		assert.equal(entries.at(-1)?.phase, "generate");
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const pass = await tool.execute("verify-pass", { workset_checks: [{ id: "S1", status: "completed", evidence: "Main scene created" }] }, undefined, undefined, ctx);
		assert.match(pass.content[0].text, /Godot PASS/);
		assert.equal(plannerCalls, 2);
		assert.equal(entries.at(-1)?.phase, "review");
		const blockedShell = await handlers.get("tool_call")?.({ toolName: "bash", input: { command: "echo changed > Main.tscn" } }, ctx) as { block: boolean; reason: string };
		assert.equal(blockedShell.block, true, "shell commands can modify files and must be blocked during review");
		assert.equal(await handlers.get("tool_call")?.({ toolName: "read", input: { path: "Main.tscn" } }, ctx), undefined);
		assert.deepEqual(entries.at(-1)?.solved.map((item) => item.id), ["S1"]);
		const reviewPhase = await handlers.get("context_with_system")?.({ messages: phase.messages }, ctx) as { messages: { sections: Record<string, string> }[] };
		assert.match(reviewPhase.messages[0].sections["ltgd-current-state"], /Phase: review/);
		assert.equal(Object.keys(reviewPhase.messages[0].sections).filter((key) => key === "ltgd-current-state").length, 1);
		const savedAttempts = entries.at(-1)?.attempts;
		const select = tools.get("godot_set_project") as TestTool;
		await assert.rejects(() => select.execute("reset-review", { requirements: [{ id: "R2", text: "New objective" }] }, undefined, undefined, ctx), /new_task/);
		assert.equal(entries.at(-1)?.phase, "review");
		const cached = await tool.execute("verify-cached", {}, undefined, undefined, ctx);
		assert.match(cached.content[0].text, /reused the last successful verification/);
		assert.equal(entries.at(-1)?.attempts, savedAttempts);
		const finish = tools.get("godot_finish") as TestTool;
		const missing = await finish.execute("review-missing", { checks: [{ id: "R1", status: "missing", expected: "Requested interaction exists", observed: "It is absent", evidence: "A requested interaction is absent" }] }, undefined, undefined, ctx);
		assert.match(missing.content[0].text, /Review found missing/);
		assert.equal(entries.at(-1)?.phase, "generate");
		const noChange = await tool.execute("verify-before-fix", { workset_checks: [{ id: "R1", status: "completed", evidence: "No changes yet" }] }, undefined, undefined, ctx);
		assert.match(noChange.content[0].text, /No project files changed/);
		assert.equal(entries.at(-1)?.attempts, savedAttempts);
		await fs.writeFile(path.join(root, "asset-notes.txt"), "new asset content");
		const afterMissing = await tool.execute("verify-missing-fix", { workset_checks: [{ id: "R1", status: "completed", evidence: "Missing interaction added" }] }, undefined, undefined, ctx);
		assert.match(afterMissing.content[0].text, /Godot PASS/);
		assert.equal(entries.at(-1)?.phase, "review");
		await fs.writeFile(path.join(root, "asset-notes.txt"), "revised asset content");
		await assert.rejects(() => finish.execute("finish-stale", { checks: [{ id: "R1", status: "implemented", evidence: "Scene built" }] }, undefined, undefined, ctx), /Verify the current project files/);
		await assert.rejects(() => tool.execute("verify-unjustified", {}, undefined, undefined, ctx), /reopen_requirement_id/);
		const beforeInvalidReopen = entries.length;
		await assert.rejects(() => tool.execute("verify-invalid-reopen", { reopen_requirement_id: "R1", workset_checks: [{ id: "R2", status: "completed", evidence: "Wrong ID" }] }, undefined, undefined, ctx), /Unknown active workset ID/);
		assert.equal(entries.length, beforeInvalidReopen, "invalid reopen reports must not persist a state change");
		const unresolvedReopen = await tool.execute("verify-unresolved-reopen", { reopen_requirement_id: "R1", workset_checks: [{ id: "R1", status: "unresolved", evidence: "The changed asset still needs integration" }] }, undefined, undefined, ctx);
		assert.match(unresolvedReopen.content[0].text, /Current review workset is incomplete/);
		assert.equal(entries.length, beforeInvalidReopen);
		assert.equal(entries.at(-1)?.phase, "review");
		const afterAsset = await tool.execute("verify-asset", { reopen_requirement_id: "R1", workset_checks: [{ id: "R1", status: "completed", evidence: "Asset integrated" }] }, undefined, undefined, ctx);
		assert.match(afterAsset.content[0].text, /Godot PASS/);
		assert.equal(entries.at(-1)?.phase, "review");
		const done = await finish.execute("finish", { checks: [{ id: "R1", status: "implemented", evidence: "Boot report and route checked" }] }, undefined, undefined, ctx);
		assert.match(done.content[0].text, /Task recorded as done/);
		assert.equal(entries.at(-1)?.phase, "done");
		await handlers.get("agent_end")?.({}, ctx);
		await assert.rejects(() => tool.execute("verify-after-done", {}, undefined, undefined, ctx), /task has ended/);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("scene inspection and Godot verification run in the selected project", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-test-"));
	const project = path.join(root, "game");
	await fs.mkdir(project);
	await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
	const before = await inspectProject(project);
	assert.equal(before.mainScene, "res://Main.tscn");
	assert.equal((await inspectScene(project, "Main.tscn") as { nodes: unknown[] }).nodes.length, 1);
	const pass = await verifyProject({ project, godot });
	assert.equal(pass.status, "pass", JSON.stringify(pass));
	assert.equal((await inspectProject(project)).fingerprint, before.fingerprint);
	assert.equal((await fs.stat(path.join(project, ".godot"))).isDirectory(), true, "Godot import should write its cache in the selected project");
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"\n');
	const fail = await verifyProject({ project, godot });
	assert.equal(fail.status, "fail", JSON.stringify(fail));
	assert.ok(fail.errors.length > 0);
	assert.ok(parseGodotErrors('ERROR: res://Main.tscn:3 - Parse Error: Expected "]".', "import").length > 0);
	assert.notEqual(fail.fingerprint, before.fingerprint);
	assert.equal((await fs.readdir(root)).includes("runs"), false, "verification must not create a runs directory");
	if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary test directory.");
	await fs.rm(root, { recursive: true, force: true });
});

test("LTGD CMD launcher adds PaT without Pi developer resources", async () => {
	const launcher = path.resolve(import.meta.dirname, "../start.cmd");
	const cwd = path.resolve(import.meta.dirname, "../..");
	const response = await new Promise<string>((resolve, reject) => {
		const child = spawn("cmd.exe", ["/d", "/c", launcher, "--mode", "rpc", "--offline", "--no-session", "--no-approve"], { cwd, windowsHide: true });
		let output = "";
		let errors = "";
		const timeout = setTimeout(() => { child.kill(); reject(new Error(`Pi RPC timed out: ${errors}\n${output}`)); }, 20_000);
		child.stdout.on("data", (chunk: Buffer) => {
			output += chunk.toString();
			if (output.includes('"command":"get_commands"')) {
				clearTimeout(timeout);
				child.stdin.end();
				child.kill();
				resolve(output);
			}
		});
		child.stderr.on("data", (chunk: Buffer) => { errors += chunk.toString(); });
		child.on("error", (error) => { clearTimeout(timeout); reject(error); });
		child.on("exit", (code) => {
			if (!output.includes('"command":"get_commands"')) {
				clearTimeout(timeout);
				reject(new Error(`Pi RPC exited ${code}: ${errors}\n${output}`));
			}
		});
		child.stdin.write('{"id":"ltgd-check","type":"get_commands"}\n');
	});
	assert.match(response, /godot-status/);
	for (const name of ["skill:add-llm-provider", "skill:interactive-testing", "skill:release", '"name":"deslop"', "import-repro.ts", "redraws.ts"]) {
		assert.ok(!response.includes(name), `Unexpected Pi developer resource ${name}: ${response}`);
	}
});
