import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { parseContractItems } from "../godot-pat/contract.ts";
import { acceptPlan, activeWorkset, finishTask, migrateTaskState, newTask, recordVerification, validateWorksetChecks,
	type DecompositionPlan, type TaskState, type Verification } from "../godot-pat/controller.ts";
import { classifyGodotDiagnostics, parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
import godotPat from "../godot-pat/index.ts";
import { parsePlannerOutput, plannerInput } from "../godot-pat/planner.ts";
import { inspectProject, inspectScene } from "../godot-pat/project.ts";

const godot = path.resolve(import.meta.dirname, "../../Godot_Engine/Godot_v4.6.2-stable_win64_console.exe");
type TestTool = { execute: (id: string, params: object, signal?: undefined, update?: undefined, context?: object) => Promise<{ content: { text: string }[] }> };

test("one extraction validates source quotes and creates the original requirement list", () => {
	const sources = [{ id: "user_request", text: "Make scanning and jamming work" }, { id: "file:task.toml", text: "audio = true" }];
	const raw = JSON.stringify({ requirements: [
		{ text: "Scan signals", doneWhen: "Scanning returns a signal", sourceEvidence: [{ sourceId: "user_request", quote: "scanning" }] },
		{ text: "Audio cues", doneWhen: "Audio plays", sourceEvidence: [{ sourceId: "file:task.toml", quote: "audio = true" }] },
	] });
	const requirements = parseContractItems(raw, sources);
	assert.deepEqual(requirements.map((item) => item.id), ["R1", "R2"]);
	assert.equal(newTask("Make scanning and jamming work", requirements, sources).requirements[1].text, "Audio cues");
	assert.throws(() => parseContractItems(raw.replace("audio = true", "nonexistent"), sources), /match a supplied source/);
});

test("Controller extracts once from task.toml and instruction.md before generation", async () => {
	const cwd = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-contract-"));
	try {
		await fs.writeFile(path.join(cwd, "instruction.md"), "Radio scanning\n");
		await fs.writeFile(path.join(cwd, "task.toml"), "jamming = true\n");
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		let calls = 0;
		godotPat({ on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); } } as unknown as ExtensionAPI);
		const ctx = { cwd, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { messages: { content: { text: string }[] }[] }) {
				calls++;
				const sources = JSON.parse(request.messages[0].content[0].text).sources as { id: string; text: string }[];
				assert.equal(sources.length, 3);
				const instruction = sources.find((item) => item.id.endsWith("instruction.md"))!;
				const task = sources.find((item) => item.id.endsWith("task.toml"))!;
				const requirements = [
					{ text: "Radio scanning", doneWhen: "Radio scans", sourceEvidence: [{ sourceId: instruction.id, quote: "Radio scanning" }] },
					{ text: "Jamming", doneWhen: "Signal can jam", sourceEvidence: [{ sourceId: task.id, quote: "jamming = true" }] },
				];
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify({ requirements }) }] }) };
			} }, sessionManager: { getBranch: () => [] } };
		await handlers.get("session_start")?.({}, ctx);
		await handlers.get("input")?.({ source: "user", text: "Build the game from task.toml" }, ctx);
		await (tools.get("godot_set_project") as TestTool).execute("select", {}, undefined, undefined, ctx);
		assert.equal(calls, 1, "normal initialization uses one extraction request");
		assert.deepEqual(entries.at(-1)?.requirements.map((item) => item.text), ["Radio scanning", "Jamming"]);
		assert.equal(tools.has("godot_propose_work"), false);
		assert.equal(tools.has("godot_decompose_work"), false);
		assert.equal(entries.at(-1)?.schemaVersion, 7);
	} finally {
		if (!cwd.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary directory.");
		await fs.rm(cwd, { recursive: true, force: true });
	}
});

test("direct-first flow plans only after failure and repairs missing original requirements directly", () => {
	const requirements = [{ id: "R1", text: "Menu" }, { id: "R2", text: "Jamming" }];
	const initial = newTask("Build a game", requirements);
	assert.deepEqual(activeWorkset(initial).items.map((item) => item.id), ["R1", "R2"]);
	assert.throws(() => validateWorksetChecks(initial, [{ id: "R1", status: "completed", evidence: "Menu created" }]), /Missing: R2/);
	assert.equal(validateWorksetChecks(initial, [
		{ id: "R1", status: "completed", evidence: "Menu created" },
		{ id: "R2", status: "unresolved", evidence: "Jamming absent" },
	]).unresolved.length, 1);
	const failure: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "Scene parse error" }], score: 0, fingerprint: "a" };
	const planning = recordVerification(initial, failure);
	assert.equal(planning.phase, "plan");
	const plan: DecompositionPlan = { decision: "revise", reason: "Scene fails to parse", objective: "Fix import",
		subtasks: [{ id: "S1", problem: "Parse error", goal: "Fix scene" }] };
	const executing = acceptPlan(planning, plan);
	assert.deepEqual(activeWorkset(executing).items, [{ id: "S1", goal: "Fix scene" }]);
	const reviewed = recordVerification(executing, { ...failure, status: "pass", errors: [], score: 10, fingerprint: "b" });
	assert.equal(reviewed.phase, "review");
	const missing = finishTask(reviewed, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R2", status: "missing", evidence: "No jamming behavior" },
	], "b");
	assert.equal(missing.phase, "generate");
	assert.deepEqual(missing.pendingRequirementIds, ["R2"]);
	assert.deepEqual(activeWorkset(missing).items, [{ id: "R2", goal: "Jamming" }]);
	const passedAgain = recordVerification(missing, { ...failure, status: "pass", errors: [], score: 10, fingerprint: "c" });
	assert.equal(finishTask(passedAgain, [
		{ id: "R1", status: "implemented", evidence: "Menu scene" },
		{ id: "R2", status: "needs_playtest", evidence: "Jamming code exists; timing needs playtest" },
	], "c").phase, "done");
});

test("repeated identical failures stop while changed errors can continue", () => {
	const failure: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "same error" }], score: 0, fingerprint: "a" };
	const first = recordVerification(newTask("Game"), failure);
	assert.equal(recordVerification(first, failure).phase, "stopped");
	const revised = acceptPlan(first, { decision: "revise", reason: "Fix import", objective: "Import", subtasks: [{ id: "S1", problem: "Parse", goal: "Fix" }] });
	const second = recordVerification(revised, { ...failure, fingerprint: "b" });
	assert.equal(second.phase, "plan");
	const third = recordVerification(acceptPlan(second, { decision: "revise", reason: "Still fails", objective: "Import", subtasks: [{ id: "S1", problem: "Parse", goal: "Fix" }] }), { ...failure, fingerprint: "c" });
	assert.equal(third.phase, "stopped");
	assert.equal(recordVerification(revised, { ...failure, fingerprint: "b", errors: [{ stage: "import", message: "different" }] }).phase, "plan");
	const stopped = acceptPlan(first, { decision: "cannot_resolve_in_project", reason: "No project fix", evidence: ["No source location"] });
	assert.equal(stopped.phase, "stopped");
});

test("older state migrates without work lineage or scope records", () => {
	const old = { ...newTask("Game"), schemaVersion: 6, pendingRequirements: ["R1"], lastFailure: "sig",
		workItems: [{ id: "W1" }], suggestions: [{ reason: "optional" }] };
	const state = migrateTaskState(old);
	assert.equal(state.schemaVersion, 7);
	assert.deepEqual(state.pendingRequirementIds, ["R1"]);
	assert.equal(state.lastFailureSignature, "sig");
	assert.equal("workItems" in state, false);
	assert.equal("suggestions" in state, false);
});

test("Planner receives all failure errors and nearby code without reading outside the project", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-planner-input-"));
	try {
		await fs.writeFile(path.join(root, "Player.gd"), ["extends Node", "", "func play():", ...Array.from({ length: 45 }, (_, i) => `\tvar value_${i} = ${i}`)].join("\n"));
		const errors = Array.from({ length: 20 }, (_, index) => ({ stage: "import", file: "res://Player.gd", line: index + 15, message: `error ${index}: ${"x".repeat(500)}` }));
		errors.push({ stage: "import", file: "../outside.gd", line: 1, message: "outside" });
		const state = recordVerification(newTask("Build a game"), { status: "fail", stage: "import", errors, score: 0, fingerprint: "x" });
		const input = JSON.parse(await plannerInput(state, { project: root, mainScene: "res://Main.tscn", scenes: [], scripts: ["Player.gd"], resources: 2, fingerprint: "x" }));
		assert.equal(input.latest_failure.errors.length, 21);
		assert.equal(input.current_code.length, 1);
		assert.match(input.current_code[0].code, /func play\(\):/);
		assert.ok(input.code_unavailable.some((item: { file: string }) => item.file === "../outside.gd"));
		assert.equal("authorized_work" in input, false);
		assert.equal("completed_subtasks" in input, false);
		assert.equal(parsePlannerOutput('{"decision":"revise","reason":"r","objective":"x","subtasks":[{"id":"S1","problem":"p","goal":"g"}]}').objective, "x");
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("Godot diagnostics retain distinct errors and treat exit cleanup as nonblocking", () => {
	const lines = Array.from({ length: 20 }, (_, index) => `ERROR: res://scripts/Player.gd:${index + 1} - failure ${index} ${"x".repeat(500)}`);
	const output = `${lines[0]}\n${"ordinary output\n".repeat(150_000)}${lines.slice(1).join("\n")}\n${lines[0]}\n`;
	assert.equal(parseGodotErrors(output, "import").length, 20);
	const cleanup = "ERROR: 4 resources still in use at exit (run with --verbose for details).";
	const scriptError = "SCRIPT ERROR: Invalid call in res://Player.gd:25";
	assert.equal(classifyGodotDiagnostics(parseGodotErrors(`${cleanup}\n`, "runtime")).blocking.length, 0);
	assert.equal(classifyGodotDiagnostics(parseGodotErrors(`${scriptError}\n${cleanup}\n`, "runtime")).blocking.length, 1);
});

test("failed Godot verification calls Planner once; PASS review blocks edits; missing returns to generation", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-flow-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
		const tools = new Map<string, unknown>();
		const entries: TaskState[] = [];
		let plannerCalls = 0;
		godotPat({ on(name: string, handler: (event: unknown, ctx: unknown) => unknown) { handlers.set(name, handler); },
			registerTool(tool: { name: string }) { tools.set(tool.name, tool); }, registerCommand() {},
			appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); } } as unknown as ExtensionAPI);
		const ctx = { cwd: root, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
			modelRegistry: { streamSimple(_model: unknown, request: { messages: { content: { text: string }[] }[] }) {
				plannerCalls++;
				const input = JSON.parse(request.messages[0].content[0].text);
				assert.equal(input.latest_failure.errors.length > 0, true);
				assert.equal("authorized_work" in input, false);
				return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify({
					decision: "revise", reason: "Missing main scene", objective: "Make scene import",
					subtasks: [{ id: "S1", problem: "No scene", goal: "Create Main.tscn" }],
				}) }] }) };
			} }, sessionManager: { getBranch: () => [{ type: "custom", customType: "godot-pat-state", data: { ...newTask("Build a game"), projectPath: root } }] } };
		await handlers.get("session_start")?.({}, ctx);
		const verify = tools.get("godot_verify") as TestTool;
		const unresolved = await verify.execute("unresolved", { workset_checks: [{ id: "R1", status: "unresolved", evidence: "Scene absent" }] }, undefined, undefined, ctx);
		assert.match(unresolved.content[0].text, /Godot verification was not run/);
		assert.equal(plannerCalls, 0);
		const failed = await verify.execute("fail", { workset_checks: [{ id: "R1", status: "completed", evidence: "Project created" }] }, undefined, undefined, ctx);
		assert.match(failed.content[0].text, /Godot FAIL/);
		assert.equal(plannerCalls, 1);
		assert.equal(entries.at(-1)?.phase, "generate");
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const passed = await verify.execute("pass", { workset_checks: [{ id: "S1", status: "completed", evidence: "Scene created" }] }, undefined, undefined, ctx);
		assert.match(passed.content[0].text, /Godot PASS/);
		assert.equal(entries.at(-1)?.phase, "review");
		await handlers.get("input")?.({ source: "user", text: "Please polish the game" }, ctx);
		const blocked = await handlers.get("tool_call")?.({ toolName: "bash", input: { command: "echo change" } }, ctx) as { block: boolean };
		assert.equal(blocked.block, true);
		assert.equal(await handlers.get("tool_call")?.({ toolName: "read", input: { path: "Main.tscn" } }, ctx), undefined);
		const finish = tools.get("godot_finish") as TestTool;
		await finish.execute("missing", { checks: [{ id: "R1", status: "missing", evidence: "Requested action absent" }] }, undefined, undefined, ctx);
		assert.equal(entries.at(-1)?.phase, "generate");
		assert.deepEqual(entries.at(-1)?.pendingRequirementIds, ["R1"]);
		const unchanged = await verify.execute("unchanged", { workset_checks: [{ id: "R1", status: "completed", evidence: "No changes" }] }, undefined, undefined, ctx);
		assert.match(unchanged.content[0].text, /No project files changed/);
		await fs.writeFile(path.join(root, "feature.txt"), "Implemented requested action");
		const repaired = await verify.execute("repair", { workset_checks: [{ id: "R1", status: "completed", evidence: "Feature added" }] }, undefined, undefined, ctx);
		assert.match(repaired.content[0].text, /Godot PASS/);
		await finish.execute("done", { checks: [{ id: "R1", status: "implemented", evidence: "Feature file and scene" }] }, undefined, undefined, ctx);
		assert.equal(entries.at(-1)?.phase, "done");
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("scene inspection and Godot verification use the selected project", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-project-"));
	try {
		await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
		const before = await inspectProject(root);
		assert.equal(before.mainScene, "res://Main.tscn");
		assert.equal((await inspectScene(root, "Main.tscn") as { nodes: unknown[] }).nodes.length, 1);
		assert.equal((await verifyProject({ project: root, godot })).status, "pass");
		assert.equal((await inspectProject(root)).fingerprint, before.fingerprint);
		assert.equal((await fs.stat(path.join(root, ".godot"))).isDirectory(), true);
	} finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
});

test("LTGD CMD launcher loads PaT without Pi developer resources", async () => {
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
			if (!output.includes('"command":"get_commands"')) { clearTimeout(timeout); reject(new Error(`Pi RPC exited ${code}: ${errors}\n${output}`)); }
		});
		child.stdin.write('{"id":"ltgd-check","type":"get_commands"}\n');
	});
	assert.match(response, /godot-status/);
	for (const name of ["skill:add-llm-provider", "skill:interactive-testing", "skill:release", '"name":"deslop"', "import-repro.ts", "redraws.ts"]) {
		assert.ok(!response.includes(name), `Unexpected Pi developer resource ${name}: ${response}`);
	}
});
