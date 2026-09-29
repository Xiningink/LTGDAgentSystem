import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { acceptPlan, completeSubtask, newTask, recordVerification, type Verification } from "../godot-pat/controller.ts";
import { parseGodotErrors, verifyProject } from "../godot-pat/godot.ts";
import { inspectProject, inspectScene } from "../godot-pat/project.ts";

const godot = path.resolve(import.meta.dirname, "../../Godot_Engine/Godot_v4.6.2-stable_win64_console.exe");

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
	assert.equal(completeSubtask(verifiedStep, "Scene transition observed", "c").phase, "done");
	assert.throws(() => completeSubtask(verifiedStep, "", "c"));
	assert.equal(recordVerification(plan, { ...failure, fingerprint: "b" }).phase, "stopped");
	assert.equal(recordVerification(repair, { ...failure, status: "pass", score: 10 }).phase, "done");
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
	const cwd = path.resolve(import.meta.dirname, "../../games/system");
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
