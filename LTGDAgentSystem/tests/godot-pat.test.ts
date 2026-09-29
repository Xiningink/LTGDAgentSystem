import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { acceptPlan, activeWorkset, finishTask, generatorHandoff, newTask, recordVerification, type DecompositionPlan, type TaskState, type Verification } from "../godot-pat/controller.ts";
import { classifyGodotDiagnostics, parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
import { parseReviewOutput, reviewInput, REVIEW_SYSTEM_PROMPT } from "../godot-pat/executor.ts";
import godotPat from "../godot-pat/index.ts";
import { parsePlannerOutput, plannerInput } from "../godot-pat/planner.ts";
import { inspectProject, inspectScene } from "../godot-pat/project.ts";

const godot = path.resolve(import.meta.dirname, "../../Godot_Engine/Godot_v4.6.2-stable_win64_console.exe");

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
		const ctx = { cwd, sessionManager: { getBranch: () => [] } };
		await handlers.get("session_start")?.({}, ctx);
		assert.equal(handlers.has("tool_call"), true, "LTGD guards review after a Godot pass");
		assert.equal(handlers.get("tool_call")?.({ toolName: "bash" }, ctx), undefined, "unrelated Pi tools remain available before a game task starts");
		assert.equal(handlers.has("agent_end"), false, "unrelated turns must not trigger automatic Godot verification");
		const unrelated = await handlers.get("before_agent_start")?.({ prompt: "List my notes", systemPrompt: "BASE" }, ctx) as { systemPrompt: string };
		assert.match(unrelated.systemPrompt, /For other tasks, leave LTGD tools unused/);
		assert.equal(entries.length, 0, "an unrelated request must not start a Godot task");
		await handlers.get("input")?.({ source: "user", text: "Build in output/AS/HorrorSignalLost" }, ctx);
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
		assert.deepEqual((entries.at(-1) as TaskState).requirements, [{ id: "R1", text: "Start a new game without an output path" }]);
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
	const reviewed = recordVerification(executing, { ...failure, status: "pass", score: 10, fingerprint: "c" });
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

test("review checks fixed requirements and sends only real gaps to Planner", () => {
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
	assert.equal(missing.phase, "plan");
	assert.deepEqual(missing.pendingRequirements, ["R2"]);
	assert.equal(missing.plan.length, 0);
	assert.equal(missing.lastReviewFailureFingerprint, "current");
	assert.throws(() => finishTask(missing, [], "current"), /successful full-project review/);
	const plannedAfterGap = acceptPlan(missing, { decision: "revise", reason: "Signal collection is absent", objective: "Implement signal collection", subtasks: [{ id: "S1", problem: "Original R2 missing", goal: "Add the interaction" }] });
	assert.equal(plannedAfterGap.pendingRequirements, undefined, "the Planner handoff should take priority after a failed repair");
	assert.deepEqual(activeWorkset(plannedAfterGap), { source: "planner", items: [{ id: "S1", goal: "Add the interaction" }] });
	const done = finishTask(reviewed, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R2", status: "implemented", evidence: "Collection interaction exists" },
	], "current");
	assert.equal(done.phase, "done");
	assert.deepEqual(done.completionEvidence?.[1], { id: "R2", status: "implemented", evidence: "Collection interaction exists" });
	assert.throws(() => finishTask(reviewed, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R2", status: "needs_playtest" as "implemented", evidence: "Unverified" },
	], "current"), /Invalid status/);
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
		assert.equal("completed_subtasks" in input, false);
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
			modelRegistry: { streamSimple() {
				calls++;
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: calls === 1 ? "invalid" : JSON.stringify({
					decision: "revise", reason: "Scene is missing", objective: "Create scene", subtasks: [{ id: "S1", problem: "Scene is missing", goal: "Create scene", suggested_files: ["Main.tscn"] }],
				}) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		const resumed = await handlers.get("agent_before_settle")?.({ outcome: "completed", entries: [] }, ctx) as { entries: { content: string }[]; continue: boolean };
		assert.equal(calls, 2);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.match(resumed.entries.at(-1)?.content ?? "", /Generator plan/);
		assert.equal(resumed.continue, true);
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
		const result = await handlers.get("agent_before_settle")?.({ outcome: "completed", entries: [] }, ctx) as { entries: { content: string }[]; continue: boolean };
		assert.equal(calls, 1);
		assert.match(result.entries.at(-1)?.content ?? "", /Stop automatic retries/);
		assert.doesNotMatch(result.entries.at(-1)?.content ?? "", /Generator plan/);
		assert.equal(result.continue, false);
		assert.equal(entries.at(-1)?.phase, "stopped");
		assert.equal(entries.at(-1)?.lastVerification?.status, "fail");
		assert.equal(await handlers.get("agent_before_settle")?.({ outcome: "completed", entries: [] }, ctx), undefined);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("Executor automatically verifies, reviews, and plans only confirmed failures", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-executor-loop-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		const requests: { systemPrompt: string; input: string }[] = [];
		let reviewCalls = 0;
		const initial = { ...newTask("Build a game with signal scanning"), projectPath: root, solved: [{ id: "old", evidence: "self-report", fingerprint: "old" }] };
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); },
			registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
		} as unknown as ExtensionAPI);
		const ctx = {
			cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string; messages: { content: { text: string }[] }[] }) {
				const input = request.messages[0].content[0].text;
				requests.push({ systemPrompt: request.systemPrompt, input });
				const review = request.systemPrompt === REVIEW_SYSTEM_PROMPT;
				const output = review
					? { checks: [{ id: "R1", status: reviewCalls++ === 0 ? "missing" : "implemented", evidence: reviewCalls === 1 ? "The scan action is absent" : "Game.gd defines scan()" }] }
					: { decision: "revise", reason: "Repair the latest Executor failure", objective: "Make the requested game work", subtasks: [{ id: "S1", problem: "Latest confirmed failure", goal: "Repair only that failure" }] };
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(output) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: initial }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		assert.equal(tools.has("godot_verify"), false);
		assert.equal(tools.has("godot_finish"), false);
		const prompt = await handlers.get("before_agent_start")?.({ prompt: "Build the game", systemPrompt: "BASE" }, ctx) as { systemPrompt: string };
		assert.match(prompt.systemPrompt, /STOP using tools and end this Generator turn/);
		const settle = async () => handlers.get("agent_before_settle")?.({ outcome: "completed", entries: [] }, ctx) as Promise<{ entries: { content: string }[]; continue: boolean }>;
		assert.equal(await handlers.get("agent_before_settle")?.({ outcome: "aborted", entries: [] }, ctx), undefined);
		const first = await settle();
		assert.equal(first.continue, true);
		assert.match(first.entries.at(-1)?.content ?? "", /Godot FAIL/);
		assert.match(first.entries.at(-1)?.content ?? "", /Generator plan/);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.equal("solved" in (entries.at(-1) ?? {}), false);
		assert.deepEqual(Object.keys(JSON.parse(requests[0].input)), ["original_requirement", "project_overview", "latest_failure", "current_code", "code_unavailable"]);
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const second = await settle();
		assert.equal(second.continue, true);
		assert.match(second.entries.at(-1)?.content ?? "", /Godot PASS/);
		assert.match(second.entries.at(-1)?.content ?? "", /missing original requirements/);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.equal(reviewCalls, 1);
		assert.ok(requests.some((item) => JSON.parse(item.input).latest_requirement_failure), "Planner receives the review failure rather than a fabricated Godot error");
		await fs.writeFile(path.join(root, "Game.gd"), 'extends Node\nfunc scan():\n\tpass\n');
		const third = await settle();
		assert.equal(third.continue, false);
		assert.match(third.entries.at(-1)?.content ?? "", /Task recorded as done/);
		assert.equal(entries.at(-1)?.phase, "done");
		assert.equal(reviewCalls, 2);
		assert.equal(await settle(), undefined, "done must not start another Generator turn");
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("Executor review reads referenced task files and ignores optional polish", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-executor-input-"));
	try {
		const task = path.join(root, "tasks", "signal");
		const project = path.join(root, "game");
		await fs.mkdir(task, { recursive: true });
		await fs.mkdir(project);
		await fs.writeFile(path.join(task, "instruction.md"), "Build the radio scanning interaction.");
		await fs.writeFile(path.join(task, "task.toml"), 'name = "Signal"\n');
		await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const index = await inspectProject(project);
		const state = recordVerification(newTask("Read tasks\\signal and build the game"), { status: "pass", stage: "runtime", errors: [], score: 10, fingerprint: index.fingerprint });
		const input = JSON.parse(await reviewInput(state, index, root));
		assert.deepEqual(input.specification_files.map((item: { file: string }) => item.file), ["tasks/signal/instruction.md", "tasks/signal/task.toml"]);
		assert.ok(input.project_text.some((item: { file: string }) => item.file === "Main.tscn"));
		assert.match(REVIEW_SYSTEM_PROMPT, /optional polish/);
		assert.deepEqual(parseReviewOutput('{"checks":[{"id":"R1","status":"implemented","evidence":"Main.tscn"}]}'), [{ id: "R1", status: "implemented", evidence: "Main.tscn" }]);
		assert.throws(() => parseReviewOutput("not json"));
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("Executor stops an unchanged requirement repair before repeating review", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-unchanged-review-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const project = await inspectProject(root);
		const reviewed = recordVerification(newTask("Build a signal game"), { status: "pass", stage: "runtime", errors: [], score: 10, fingerprint: project.fingerprint });
		const missing = finishTask(reviewed, [{ id: "R1", status: "missing", evidence: "Signal interaction absent" }], project.fingerprint);
		const saved = { ...acceptPlan(missing, { decision: "revise", reason: "Required interaction absent", objective: "Add scan", subtasks: [{ id: "S1", problem: "No scan", goal: "Implement scan" }] }), projectPath: root };
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const entries: TaskState[] = [];
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool() {}, registerCommand() {}, appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
		} as unknown as ExtensionAPI);
		const ctx = { cwd: root, sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] } };
		await handlers.get("session_start")?.({}, ctx);
		const result = await handlers.get("agent_before_settle")?.({ outcome: "completed", entries: [] }, ctx) as { entries: { content: string }[]; continue: boolean };
		assert.equal(result.continue, false);
		assert.match(result.entries.at(-1)?.content ?? "", /project has not changed/);
		assert.equal(entries.at(-1)?.phase, "stopped");
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
