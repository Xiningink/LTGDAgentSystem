import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { acceptPlan, finishTask, generatorHandoff, newTask, recordCompletedSubtasks, recordVerification, type DecompositionPlan, type TaskState, type Verification } from "../godot-pat/controller.ts";
import { parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
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
		assert.equal(handlers.has("tool_call"), false, "loading LTGD must not block ordinary Pi tools");
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
		await select.execute("select", { project: "output/AS/HorrorSignalLost" }, undefined, undefined, ctx);
		assert.equal((entries.at(-1) as { projectPath: string }).projectPath, explicit);
		assert.equal(await fs.stat(explicit).then((item) => item.isDirectory()), true);
		assert.equal(await fs.stat(path.join(cwd, "game")).then(() => true, () => false), false);
		await fs.writeFile(path.join(explicit, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		await fs.writeFile(path.join(explicit, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const inspected = await inspect.execute("inspect", {}, undefined, undefined, ctx);
		assert.equal(JSON.parse(inspected.content[0].text).mainScene, "res://Main.tscn");
		await handlers.get("input")?.({ source: "user", text: "Start a new game without an output path" }, ctx);
		await select.execute("select", { new_task: true }, undefined, undefined, ctx);
		assert.equal((entries.at(-1) as { projectPath: string }).projectPath, path.join(cwd, "game"));
		assert.equal(await fs.stat(path.join(cwd, "game")).then((item) => item.isDirectory()), true);
		assert.equal(ctx.cwd, cwd);
	} finally {
		if (!cwd.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(cwd, { recursive: true, force: true });
	}
});

test("first failed verification plans immediately; one full-plan pass enters review", () => {
	const failure: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "parse error" }], score: 0, fingerprint: "a" };
	const plan = recordVerification(newTask("Build a game"), failure);
	assert.equal(plan.phase, "plan");
	const decomposition: DecompositionPlan = {
		objective: "Make the main scene import and start",
		subtasks: [
			{ id: "S1", problem: "Scene import fails", goal: "Fix scene", suggested_files: ["Main.tscn"] },
			{ id: "S2", problem: "Route is not connected", goal: "Wire game route", suggested_files: ["Route.gd"] },
		],
	};
	const executing = acceptPlan(plan, decomposition);
	assert.equal(executing.phase, "generate");
	assert.match(generatorHandoff(executing), /"problem":"Scene import fails"/);
	assert.match(generatorHandoff(executing), /"suggested_files":\["Route.gd"\]/);
	const progress = recordCompletedSubtasks(executing, [{ id: "S1", evidence: "Scene now imports" }], "c");
	assert.equal(progress.solved[0].id, "S1");
	assert.throws(() => recordCompletedSubtasks(executing, [{ id: "missing", evidence: "no" }], "c"));
	const reviewed = recordVerification(progress, { ...failure, status: "pass", score: 10, fingerprint: "c" });
	assert.equal(reviewed.phase, "review");
	assert.throws(() => finishTask(reviewed, [], "c"));
	assert.throws(() => finishTask(reviewed, ["booted", "gameplay checked"], "stale"));
	assert.equal(finishTask(reviewed, ["Original requirements reviewed"], "c").phase, "done");
	assert.equal(recordVerification(plan, failure).phase, "stopped");
	const directReview = recordVerification(newTask("Build a game"), { ...failure, status: "pass", score: 10 });
	assert.equal(directReview.phase, "review");
	assert.equal(finishTask(directReview, ["Original task checked"], "a").phase, "done");
	assert.throws(() => acceptPlan(plan, { ...decomposition, subtasks: [{ ...decomposition.subtasks[0], problem: "" }] }));
	assert.equal(acceptPlan(plan, { ...decomposition, subtasks: [{ ...decomposition.subtasks[0], suggested_files: ["../outside.tscn"] }] }).phase, "generate");
	assert.equal(recordVerification(executing, { ...failure, fingerprint: "d" }).phase, "plan");
	let improving = executing;
	for (let remaining = 15; remaining >= 2; remaining--) {
		improving = recordVerification(improving, { ...failure, fingerprint: `revision-${remaining}`, errors: Array.from({ length: remaining }, (_, index) => ({ stage: "import", message: `error ${index}` })) });
		assert.equal(improving.phase, "plan");
		improving = acceptPlan(improving, decomposition);
	}
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
		assert.equal(parsePlannerOutput('```json\n{"objective":"x","subtasks":[{"id":"S1","problem":"p","goal":"g"}]}\n```').objective, "x");
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
					objective: "Create scene", subtasks: [{ id: "S1", problem: "Scene is missing", goal: "Create scene", suggested_files: ["Main.tscn"] }],
				}) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: saved }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		await handlers.get("before_agent_start")?.({ prompt: "List unrelated files", systemPrompt: "BASE" }, ctx);
		assert.equal(calls, 0, "unrelated requests must not resume a pending Planner automatically");
		type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
		const resumed = await (tools.get("godot_verify") as TestTool).execute("resume-plan", {}, undefined, undefined, ctx);
		assert.equal(calls, 2);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.match(resumed.content[0].text, /Generator plan/);
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
		const decomposition: DecompositionPlan = {
			objective: "Make the game boot and navigate",
			subtasks: [{ id: "S1", problem: "Main scene is missing", goal: "Create main scene", suggested_files: ["Main.tscn"] }],
		};
		godotPat({
			on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); },
			registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
		} as unknown as ExtensionAPI);
		const ctx = {
			cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { messages: { content: { text: string }[] }[] }, options: { reasoning?: string }) {
				plannerCalls++;
				plannerRequest = request.messages[0].content[0].text;
				assert.equal(options.reasoning, undefined);
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(decomposition) }] }) };
			} },
			sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: initial }] },
		};
		await handlers.get("session_start")?.({}, ctx);
		type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };
		const tool = tools.get("godot_verify") as TestTool;
		const result = await tool.execute("verify-fail", {}, undefined, undefined, ctx);
		assert.equal(plannerCalls, 1);
		assert.equal("usage" in result, false);
		assert.deepEqual(Object.keys(JSON.parse(plannerRequest)), ["original_requirement", "project_overview", "latest_failure", "current_code", "code_unavailable", "completed_subtasks"]);
		assert.match(result.content[0].text, /"problem":"Main scene is missing"/);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.equal(tools.has("godot_plan"), false);
		assert.equal(tools.has("godot_subtask_done"), false);
		const system = { role: "system", content: "BASE", timestamp: Date.now() };
		const phase = await handlers.get("context_with_system")?.({ messages: [system] }, ctx) as { messages: { sections: Record<string, string> }[] };
		assert.match(phase.messages[0].sections["ltgd-current-state"], /subtasks: S1/);
		assert.doesNotMatch(phase.messages[0].sections["ltgd-current-state"], /"problem"/);
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"\n');
		await handlers.get("agent_end")?.({}, ctx);
		assert.equal(plannerCalls, 1, "plan execution must not auto-verify at agent_end");
		const secondFailure = await tool.execute("verify-fail-again", {}, undefined, undefined, ctx);
		assert.match(secondFailure.content[0].text, /Godot FAIL/);
		assert.equal(plannerCalls, 2);
		assert.equal(entries.at(-1)?.phase, "generate");
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const pass = await tool.execute("verify-pass", { completed_subtasks: [{ id: "S1", evidence: "Main scene created" }] }, undefined, undefined, ctx);
		assert.match(pass.content[0].text, /Godot PASS/);
		assert.equal(plannerCalls, 2);
		assert.equal(entries.at(-1)?.phase, "review");
		const reviewPhase = await handlers.get("context_with_system")?.({ messages: phase.messages }, ctx) as { messages: { sections: Record<string, string> }[] };
		assert.match(reviewPhase.messages[0].sections["ltgd-current-state"], /Phase: review/);
		assert.equal(Object.keys(reviewPhase.messages[0].sections).filter((key) => key === "ltgd-current-state").length, 1);
		const finish = tools.get("godot_finish") as TestTool;
		const done = await finish.execute("finish", { evidence: ["Boot report and route checked"] }, undefined, undefined, ctx);
		assert.match(done.content[0].text, /Task recorded as done/);
		assert.equal(entries.at(-1)?.phase, "done");
		await handlers.get("agent_end")?.({}, ctx);
		await assert.rejects(() => tool.execute("verify-after-done", {}, undefined, undefined, ctx), /task has ended/);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("scene inspection and Godot verification use a disposable project", async () => {
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
	assert.equal((await fs.readdir(project)).includes(".godot"), false);
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

test("LTGD launcher adds PaT without Pi developer resources", async () => {
	const launcher = path.resolve(import.meta.dirname, "../start.ps1");
	const cwd = path.resolve(import.meta.dirname, "../..");
	const response = await new Promise<string>((resolve, reject) => {
		const child = spawn("powershell.exe", ["-NoProfile", "-File", launcher, "--mode", "rpc", "--offline", "--no-session", "--no-approve"], { cwd, windowsHide: true });
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
