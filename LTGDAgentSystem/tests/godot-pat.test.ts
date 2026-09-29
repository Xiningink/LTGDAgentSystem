import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { acceptPlan, finishTask, newTask, recordVerification, type TaskState, type Verification } from "../godot-pat/controller.ts";
import { classifyGodotDiagnostics, parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
import { parseReviewOutput, reviewInput, REVIEW_SYSTEM_PROMPT } from "../godot-pat/executor.ts";
import godotPat from "../godot-pat/index.ts";
import { plannerInput, PLANNER_SYSTEM_PROMPT } from "../godot-pat/planner.ts";
import { inspectProject, inspectScene } from "../godot-pat/project.ts";

const godot = path.resolve(import.meta.dirname, "../../Godot_Engine/Godot_v4.6.2-stable_win64_console.exe");
type TestTool = { name: string; parameters: { properties?: Record<string, unknown> }; execute: (...args: any[]) => Promise<{ content: { text: string }[] }> };

function harness(cwd: string, saved?: unknown, responses: object[] = []) {
	const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
	const tools = new Map<string, TestTool>();
	const entries: TaskState[] = [];
	const requests: { systemPrompt: string; input: string }[] = [];
	let responseIndex = 0;
	const ctx = {
		cwd, model: { provider: "test", id: "mock" }, thinkingLevel: "off",
		modelRegistry: { streamSimple(_model: unknown, request: { systemPrompt: string; messages: { content: { text: string }[] }[] }) {
			requests.push({ systemPrompt: request.systemPrompt, input: request.messages[0].content[0].text });
			const response = responses[responseIndex++];
			return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: JSON.stringify(response) }] }) };
		} },
		sessionManager: { getBranch: () => saved ? [{ type: "custom", customType: "godot-pat-state", data: saved }] : [] },
	};
	godotPat({
		on(name: string, handler: (event: unknown, context: unknown) => unknown) { handlers.set(name, handler); },
		registerTool(tool: TestTool) { tools.set(tool.name, tool); },
		registerCommand() {},
		appendEntry(_name: string, data: unknown) { entries.push(data as TaskState); },
	} as unknown as ExtensionAPI);
	const event = (name: string, value: unknown) => handlers.get(name)?.(value, ctx);
	const settle = async () => event("agent_before_settle", { outcome: "completed", entries: [] }) as Promise<{ entries: { content: string }[]; continue: boolean } | undefined>;
	return { ctx, tools, entries, requests, event, settle };
}

async function temporaryRoot(prefix: string, run: (root: string) => Promise<void>) {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
	try { await run(root); }
	finally {
		if (!root.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary directory.");
		await fs.rm(root, { recursive: true, force: true });
	}
}

test("Pi prompt activates LTGD and discovers the user-requested project without a setup tool", async () => temporaryRoot("ltgd-select-", async (root) => {
	const app = harness(root, undefined, [{ status: "implemented", evidence: "Main scene exists" }]);
	app.event("session_start", {});
	assert.equal(app.tools.has("godot_set_project"), false);
	assert.equal(app.event("tool_call", { toolName: "bash" }), undefined);
	app.event("input", { source: "user", text: "Build a game in output/AS/Signal" });
	const prompt = app.event("before_agent_start", { prompt: "Build a game in output/AS/Signal", systemPrompt: "BASE" }) as { systemPrompt: string };
	assert.match(prompt.systemPrompt, /Executor locates that project automatically/);
	assert.equal(app.entries.at(-1)?.goal, "Build a game in output/AS/Signal");
	assert.equal(app.entries.at(-1)?.projectPath, undefined);
	const project = path.join(root, "output", "AS", "Signal");
	await fs.mkdir(project, { recursive: true });
	await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n[node name="Main" type="Node"]\n');
	const result = await app.settle();
	assert.equal(result?.continue, false);
	assert.equal(app.entries.at(-1)?.projectPath, project);
	assert.equal(app.entries.at(-1)?.phase, "done");
	assert.equal(JSON.parse(app.requests[0].input).project_directory, project);
}));

test("Project discovery reports absent or ambiguous output instead of selecting an old game", async () => temporaryRoot("ltgd-discovery-", async (root) => {
	const absent = harness(root);
	absent.event("session_start", {});
	absent.event("before_agent_start", { prompt: "Build a Godot game", systemPrompt: "BASE" });
	const noProject = await absent.settle();
	assert.match(noProject?.entries.at(-1)?.content ?? "", /No project.godot/);
	assert.equal(absent.entries.at(-1)?.phase, "stopped");
	for (const name of ["First", "Second"]) {
		const directory = path.join(root, name);
		await fs.mkdir(directory);
		await fs.writeFile(path.join(directory, "project.godot"), "config_version=5\n");
	}
	const ambiguous = harness(root);
	ambiguous.event("session_start", {});
	ambiguous.event("before_agent_start", { prompt: "Build a Godot game", systemPrompt: "BASE" });
	const manyProjects = await ambiguous.settle();
	assert.match(manyProjects?.entries.at(-1)?.content ?? "", /multiple Godot projects/);
	assert.equal(ambiguous.entries.at(-1)?.phase, "stopped");
}));

test("Project discovery can use an absolute output directory outside Pi cwd", async () => temporaryRoot("ltgd-external-", async (root) => {
	const cwd = path.join(root, "work");
	const project = path.join(root, "outside");
	await fs.mkdir(cwd);
	await fs.mkdir(project);
	const unrelated = path.join(cwd, "old-game");
	await fs.mkdir(unrelated);
	await fs.writeFile(path.join(unrelated, "project.godot"), "config_version=5\n");
	await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n[node name="Main" type="Node"]\n');
	const app = harness(cwd, undefined, [{ status: "implemented", evidence: "Main.tscn" }]);
	app.event("session_start", {});
	app.event("before_agent_start", { prompt: `Build a Godot game in "${project}"`, systemPrompt: "BASE" });
	await app.settle();
	assert.equal(app.entries.at(-1)?.projectPath, project);
	assert.equal(app.entries.at(-1)?.phase, "done");
}));

test("Controller only plans confirmed failures and completes after review", () => {
	const fail: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "parse error" }], fingerprint: "a" };
	const failed = recordVerification(newTask("Build a signal game"), fail);
	assert.equal(failed.phase, "plan");
	const planned = acceptPlan(failed, { decision: "revise", reason: "Import failed", subtasks: [{ problem: "Scene parse error", goal: "Fix the scene" }] });
	assert.equal(planned.phase, "generate");
	assert.equal(planned.plan?.length, 1);
	const passed = recordVerification(planned, { ...fail, status: "pass", stage: "runtime", errors: [], fingerprint: "b" });
	assert.equal(passed.phase, "review");
	assert.throws(() => finishTask(passed, { status: "implemented", evidence: "Main scene" }, "stale"));
	const missing = finishTask(passed, { status: "missing", evidence: "Signal scanning interaction absent" }, "b");
	assert.equal(missing.phase, "plan");
	assert.equal(missing.reviewFailure, "Signal scanning interaction absent");
	const complete = finishTask(passed, { status: "implemented", evidence: "Game.gd implements scanning" }, "b");
	assert.equal(complete.phase, "done");
	assert.equal(complete.completionEvidence, "Game.gd implements scanning");
	assert.throws(() => acceptPlan(failed, { decision: "revise", reason: "bad", subtasks: [{ problem: "", goal: "fix" }] }));
	const stopped = acceptPlan(failed, { decision: "cannot_resolve_in_project", reason: "No supported fix", evidence: ["Error has no project source"] });
	assert.equal(stopped.phase, "stopped");
	assert.match(stopped.stopReason ?? "", /No supported fix/);
});

test("Planner receives current failure evidence and cannot read outside the project", async () => temporaryRoot("ltgd-plan-", async (root) => {
	await fs.writeFile(path.join(root, "Player.gd"), "extends Node\nfunc play():\n\tpass\n");
	const errors = [{ stage: "import", file: "res://Player.gd", line: 2, message: "Parse error" }, { stage: "import", file: "../outside.gd", line: 1, message: "Outside" }];
	const failed = recordVerification(newTask("Build a game"), { status: "fail", stage: "import", errors, fingerprint: "a" });
	const overview = await inspectProject(root);
	const input = JSON.parse(await plannerInput(failed, overview));
	assert.equal(input.latest_failure.errors.length, 2);
	assert.match(input.current_code[0].code, /func play/);
	assert.ok(input.code_unavailable.some((item: { file: string }) => item.file === "../outside.gd"));
	const reviewed = finishTask(recordVerification(newTask("Build a game"), { status: "pass", stage: "runtime", errors: [], fingerprint: "a" }), { status: "missing", evidence: "Start menu absent" }, "a");
	assert.equal(JSON.parse(await plannerInput(reviewed, overview)).latest_requirement_failure, "Start menu absent");
}));

test("Godot diagnostics retain distinct script failures and ignore shutdown cleanup", () => {
	const error = "SCRIPT ERROR: Invalid call in res://Player.gd:25";
	const cleanup = "ERROR: 4 resources still in use at exit (run with --verbose for details).";
	const parsed = parseGodotErrors(`${error}\n${cleanup}\n${error}\n`, "runtime");
	assert.equal(parsed.length, 2);
	assert.equal(parsed[0].line, 25);
	const classified = classifyGodotDiagnostics(parsed);
	assert.equal(classified.blocking.length, 1);
	assert.equal(classified.warnings.length, 1);
});

test("Executor reviews task files as one original request", async () => temporaryRoot("ltgd-review-", async (root) => {
	const task = path.join(root, "tasks", "signal");
	const project = path.join(root, "game");
	await fs.mkdir(task, { recursive: true });
	await fs.mkdir(project);
	await fs.writeFile(path.join(task, "instruction.md"), "Build radio scanning.");
	await fs.writeFile(path.join(task, "task.toml"), 'name = "Signal"\n');
	await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n[node name="Main" type="Node"]\n');
	const overview = await inspectProject(project);
	const state = recordVerification(newTask("Read tasks\\signal and build the game"), { status: "pass", stage: "runtime", errors: [], fingerprint: overview.fingerprint });
	const input = JSON.parse(await reviewInput(state, overview, root));
	assert.deepEqual(input.specification_files.map((item: { file: string }) => item.file), ["tasks/signal/instruction.md", "tasks/signal/task.toml"]);
	assert.equal(input.original_request, state.goal);
	assert.equal("requirements" in input, false);
	assert.match(REVIEW_SYSTEM_PROMPT, /optional polish/);
	assert.deepEqual(parseReviewOutput('{"status":"missing","evidence":"Scanning absent"}'), { status: "missing", evidence: "Scanning absent" });
	assert.throws(() => parseReviewOutput("not json"));
}));

test("Generator handoff runs Godot, then review, and plans only observed failures", async () => temporaryRoot("ltgd-loop-", async (root) => {
	const project = path.join(root, "game");
	await fs.mkdir(project);
	await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	const repair = { decision: "revise", reason: "Repair latest failure", subtasks: [{ problem: "Confirmed failure", goal: "Repair that failure" }] };
	const app = harness(root, undefined, [
		repair,
		{ status: "missing", evidence: "The scanning interaction is absent" },
		repair,
		{ status: "implemented", evidence: "Game.gd implements scan()" },
	]);
	app.event("session_start", {});
	app.event("before_agent_start", { prompt: "Build a game with signal scanning", systemPrompt: "BASE" });
	assert.equal(await app.event("agent_before_settle", { outcome: "aborted", entries: [] }), undefined);
	const first = await app.settle();
	assert.equal(first?.continue, true);
	assert.match(first?.entries.at(-1)?.content ?? "", /Godot FAIL/);
	assert.equal(app.requests[0].systemPrompt, PLANNER_SYSTEM_PROMPT);
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n[node name="Main" type="Node"]\n');
	const second = await app.settle();
	assert.equal(second?.continue, true);
	assert.match(second?.entries.at(-1)?.content ?? "", /missing original requirement/);
	assert.equal(app.requests[1].systemPrompt, REVIEW_SYSTEM_PROMPT);
	assert.equal(app.requests[2].systemPrompt, PLANNER_SYSTEM_PROMPT);
	await fs.writeFile(path.join(project, "Game.gd"), "extends Node\nfunc scan():\n\tpass\n");
	const third = await app.settle();
	assert.equal(third?.continue, false);
	assert.equal(app.entries.at(-1)?.phase, "done");
	assert.equal(await app.settle(), undefined);
}));

test("Unchanged repair stops before another model call", async () => temporaryRoot("ltgd-unchanged-", async (root) => {
	await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	const overview = await inspectProject(root);
	const failed = recordVerification(newTask("Build game"), { status: "fail", stage: "structure", errors: [{ stage: "structure", message: "Missing scene" }], fingerprint: overview.fingerprint });
	const planned = acceptPlan(failed, { decision: "revise", reason: "Scene absent", subtasks: [{ problem: "No scene", goal: "Add scene" }] });
	const app = harness(root, { ...planned, projectPath: root });
	app.event("session_start", {});
	const result = await app.settle();
	assert.equal(result?.continue, false);
	assert.match(result?.entries.at(-1)?.content ?? "", /project has not changed/);
	assert.equal(app.requests.length, 0);
	assert.equal(app.entries.at(-1)?.phase, "stopped");
}));

test("An active previous-session review failure still reaches Planner", async () => temporaryRoot("ltgd-resume-", async (root) => {
	await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	const saved = {
		schemaVersion: 7, goal: "Build a signal game", projectPath: root, phase: "plan",
		lastVerification: { status: "pass", stage: "runtime", errors: [], fingerprint: "old" },
		lastReviewFailureFingerprint: "old",
		completionEvidence: [{ id: "R1", status: "missing", evidence: "Scanning is absent" }],
	};
	const app = harness(root, saved, [{ decision: "revise", reason: "Scanning absent", subtasks: [{ problem: "Missing interaction", goal: "Add scanning" }] }]);
	app.event("session_start", {});
	const result = await app.settle();
	assert.equal(result?.continue, true);
	assert.equal(JSON.parse(app.requests[0].input).latest_requirement_failure, "Scanning is absent");
	assert.equal(app.entries.at(-1)?.phase, "generate");
}));

test("Real Godot import and boot use the selected project", async () => temporaryRoot("ltgd-godot-", async (root) => {
	await fs.writeFile(path.join(root, "project.godot"), 'config_version=5\n[application]\nrun/main_scene="res://Main.tscn"\n');
	await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n[node name="Main" type="Node"]\n');
	assert.equal((await inspectScene(root, "Main.tscn") as { nodes: unknown[] }).nodes.length, 1);
	const pass = await verifyProject({ project: root, godot });
	assert.equal(pass.status, "pass", JSON.stringify(pass));
	assert.equal(pass.fingerprint, (await inspectProject(root)).fingerprint);
	await fs.writeFile(path.join(root, "Main.tscn"), '[gd_scene format=3]\n[node name="Main" type="Node"\n');
	const fail = await verifyProject({ project: root, godot });
	assert.equal(fail.status, "fail", JSON.stringify(fail));
	assert.ok(fail.errors.length);
}));

test("CMD launcher loads the installed Pi with LTGD", async () => {
	const launcher = path.resolve(import.meta.dirname, "../start.cmd");
	const cwd = path.resolve(import.meta.dirname, "../..");
	const response = await new Promise<string>((resolve, reject) => {
		const child = spawn("cmd.exe", ["/d", "/c", launcher, "--mode", "rpc", "--offline", "--no-session", "--no-approve"], { cwd, windowsHide: true });
		let output = "";
		let errors = "";
		const timeout = setTimeout(() => { child.kill(); reject(new Error(`Pi RPC timed out: ${errors}\n${output}`)); }, 20_000);
		child.stdout.on("data", (chunk: Buffer) => {
			output += chunk.toString();
			if (output.includes('"command":"get_commands"')) { clearTimeout(timeout); child.stdin.end(); child.kill(); resolve(output); }
		});
		child.stderr.on("data", (chunk: Buffer) => { errors += chunk.toString(); });
		child.on("error", (error) => { clearTimeout(timeout); reject(error); });
		child.on("exit", (code) => {
			if (!output.includes('"command":"get_commands"')) { clearTimeout(timeout); reject(new Error(`Pi RPC exited ${code}: ${errors}\n${output}`)); }
		});
		child.stdin.write('{"id":"ltgd-check","type":"get_commands"}\n');
	});
	assert.match(response, /godot-status/);
});
