import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { acceptPlan, completeSubtask, finishTask, newTask, recordVerification, restoreTaskState, shouldContinueAfterVerification, type Verification } from "../godot-pat/controller.ts";
import { efficiencyMode, isFullGameTask, withEfficiencyInstruction } from "../godot-pat/efficiency.ts";
import { parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
import godotPat from "../godot-pat/index.ts";
import { inspectProject, inspectScene, resolveProjectDirectory } from "../godot-pat/project.ts";

const godot = path.resolve(import.meta.dirname, "../../Godot_Engine/Godot_v4.6.2-stable_win64_console.exe");

test("project paths follow the startup directory unless explicitly selected", () => {
	const cwd = path.resolve(os.tmpdir(), "ltgd-startup");
	const selected = path.resolve(cwd, "output/AS/HorrorSignalLost");
	assert.equal(resolveProjectDirectory(cwd, "output/AS/HorrorSignalLost"), selected);
	assert.equal(resolveProjectDirectory(cwd, selected), selected);
	assert.throws(() => resolveProjectDirectory(cwd, " "));
});

test("selected delivery directory drives Godot inspection without changing Pi cwd", async () => {
	const cwd = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-project-path-"));
	const project = path.join(cwd, "output", "AS", "HorrorSignalLost");
	try {
		await fs.mkdir(project, { recursive: true });
		await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
		await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
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
		await handlers.get("input")?.({ source: "user", text: "Build in output/AS/HorrorSignalLost" }, ctx);
		type TestTool = { execute: (id: string, params: object, signal: undefined, update: undefined, context: object) => Promise<{ content: { text: string }[] }> };
		const select = tools.get("godot_set_project") as TestTool;
		const inspect = tools.get("godot_inspect_project") as TestTool;
		assert.ok(select && inspect);
		await select.execute("select", { project: "output/AS/HorrorSignalLost" }, undefined, undefined, ctx);
		const inspected = await inspect.execute("inspect", {}, undefined, undefined, ctx);
		assert.equal(JSON.parse(inspected.content[0].text).mainScene, "res://Main.tscn");
		assert.equal((entries.at(-1) as { projectPath: string }).projectPath, project);
		await handlers.get("input")?.({ source: "user", text: "Add a title screen to this game" }, ctx);
		assert.equal((entries.at(-1) as { projectPath: string }).projectPath, project);
		assert.equal(ctx.cwd, cwd);
	} finally {
		if (!cwd.startsWith(os.tmpdir() + path.sep)) throw new Error("Refusing to remove a non-temporary project directory.");
		await fs.rm(cwd, { recursive: true, force: true });
	}
});

test("direct failure gets one repair, then a planner; unchanged failure stops", () => {
	const failure: Verification = { status: "fail", stage: "import", errors: [{ stage: "import", message: "parse error" }], score: 0, fingerprint: "a", evidence: "report.json" };
	const repair = recordVerification(newTask("Build a game"), failure);
	assert.equal(repair.phase, "repair");
	const plan = recordVerification(repair, { ...failure, fingerprint: "b" });
	assert.equal(plan.phase, "plan");
	const executing = acceptPlan(plan, [{ id: "S1", goal: "Fix scene", targets: ["Main.tscn"], depends_on: [] }]);
	assert.equal(executing.phase, "execute_plan");
	const verifiedStep = recordVerification(executing, { ...failure, status: "pass", score: 10, fingerprint: "c" });
	assert.equal(verifiedStep.phase, "execute_plan");
	const reviewed = completeSubtask(verifiedStep, "Scene transition observed", "c");
	assert.equal(reviewed.phase, "verified");
	assert.equal(finishTask(reviewed, "Scene transition and input behavior checked", "c").phase, "done");
	assert.throws(() => completeSubtask(verifiedStep, "", "c"));
	assert.equal(recordVerification(plan, { ...failure, fingerprint: "b" }).phase, "stopped");
	const recovered = recordVerification(repair, { ...failure, status: "pass", score: 10 });
	assert.equal(recovered.phase, "verified");
	assert.equal(recordVerification(recovered, failure).phase, "repair");
});

test("finish requires current verification, completed subtasks, and requirement evidence", () => {
	const pass: Verification = { status: "pass", stage: "boot", errors: [], score: 10, fingerprint: "current", evidence: "report.json" };
	const verified = recordVerification(newTask("Fix a scene"), pass);
	assert.equal(verified.schemaVersion, 2);
	assert.throws(() => finishTask(newTask("Fix a scene"), "Checked scene", "current"));
	assert.throws(() => finishTask(verified, "Checked scene", "changed"));
	assert.throws(() => finishTask(verified, " ", "current"));
	const done = finishTask(verified, " Scene behavior checked ", "current");
	assert.equal(done.phase, "done");
	assert.equal(done.completionEvidence, "Scene behavior checked");
	assert.throws(() => finishTask({ ...verified, plan: [{ id: "S1", goal: "Check scene", targets: [], depends_on: [] }] }, "Checked scene", "current"));
	assert.equal(shouldContinueAfterVerification(done, pass), false);
	assert.equal(shouldContinueAfterVerification({ ...verified, phase: "stopped" }, pass), false);
	assert.equal(shouldContinueAfterVerification(verified, { ...pass, status: "fail" }), true);
	assert.equal(shouldContinueAfterVerification({ ...verified, phase: "execute_plan" }, pass), true);
});

test("only versionless legacy completion is migrated to verified", () => {
	const pass: Verification = { status: "pass", stage: "boot", errors: [], score: 10, fingerprint: "current", evidence: "report.json" };
	const done = finishTask(recordVerification(newTask("Fix a scene"), pass), "Checked scene", "current");
	assert.equal(restoreTaskState(done)?.phase, "done");
	const { schemaVersion: _version, completionEvidence: _evidence, ...legacy } = done;
	assert.equal(restoreTaskState(legacy)?.phase, "verified");
	assert.equal(restoreTaskState({ ...legacy, schemaVersion: 1 }), undefined);
});

test("efficiency policy switches without growing or retaining transcript sections", () => {
	assert.equal(isFullGameTask("制作一个完整游戏"), true);
	assert.equal(isFullGameTask("做一个游戏"), true);
	assert.equal(efficiencyMode("direct", true, true), "none");
	assert.equal(efficiencyMode("direct", false, true), "concise");
	assert.equal(efficiencyMode("repair", false, true), "diagnose");
	assert.equal(efficiencyMode("plan", false, true), "none");
	assert.equal(efficiencyMode("verified", false, true), "concise");
	assert.equal(efficiencyMode("done", false, true), "none");
	assert.equal(efficiencyMode("stopped", false, true), "none");
	assert.equal(efficiencyMode("repair", false, false), "none");

	let messages: AgentMessage[] = [
		{ role: "system", content: "Base instructions", sections: { workflow: "Keep checks" }, timestamp: 0 },
		{ role: "user", content: "Build a game", timestamp: 1 },
	];
	const history = messages[1];
	for (const [mode, expected] of [["concise", "concise"], ["diagnose", "diagnose"], ["none", null], ["concise", "concise"]] as const) {
		messages = withEfficiencyInstruction(messages, mode) ?? messages;
		assert.equal(messages.length, 2);
		assert.equal(messages[1], history);
		const leading = messages[0];
		assert.equal(leading.role, "system");
		if (leading.role !== "system") continue;
		assert.equal(leading.sections?.workflow, "Keep checks");
		assert.equal(Object.keys(leading.sections ?? {}).filter((key) => key === "ltgd_efficiency").length, 1);
		assert.equal(expected === null ? leading.sections?.ltgd_efficiency : leading.sections?.ltgd_efficiency?.includes(`efficiency: ${expected}`), expected === null ? null : true);
		if (expected === "diagnose") assert.ok(!leading.sections?.ltgd_efficiency?.includes("Prefer direct tool actions"));
		if (expected === "concise") assert.ok(!leading.sections?.ltgd_efficiency?.includes("Diagnose the latest"));
	}
});

test("scene inspection and Godot verification use a disposable project", async () => {
	const root = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-test-"));
	const project = path.join(root, "game");
	const runs = path.join(root, "runs");
	await fs.mkdir(project);
	await fs.writeFile(path.join(project, "project.godot"), 'config_version=5\n\n[application]\nrun/main_scene="res://Main.tscn"\n');
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n');
	const before = await inspectProject(project);
	assert.equal(before.mainScene, "res://Main.tscn");
	assert.equal((await inspectScene(project, "Main.tscn") as { nodes: unknown[] }).nodes.length, 1);
	const pass = await verifyProject({ project, godot, runs });
	assert.equal(pass.status, "pass", JSON.stringify(pass));
	assert.equal((await inspectProject(project)).fingerprint, before.fingerprint);
	assert.equal((await fs.readdir(project)).includes(".godot"), false);
	await fs.writeFile(path.join(project, "Main.tscn"), '[gd_scene format=3]\n\n[node name="Main" type="Node"\n');
	const fail = await verifyProject({ project, godot, runs });
	assert.equal(fail.status, "fail", JSON.stringify(fail));
	assert.ok(fail.errors.length > 0);
	assert.ok(parseGodotErrors('ERROR: res://Main.tscn:3 - Parse Error: Expected "]".', "import").length > 0);
	assert.notEqual(fail.fingerprint, before.fingerprint);
	assert.ok((await fs.readFile(fail.evidence, "utf8")).includes('"status": "fail"'));
	// Keep the transient test evidence out of the project being verified.
	assert.equal(path.dirname(fail.evidence).startsWith(runs), true);
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
