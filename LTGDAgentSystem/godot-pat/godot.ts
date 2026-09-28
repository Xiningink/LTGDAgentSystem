import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import type { Failure, Verification } from "./controller.ts";
import { inspectProject } from "./project.ts";

const EXCLUDED = new Set([".git", ".godot", ".pi", ".pi-godot", "node_modules"]);

export interface VerifyOptions {
	project: string;
	godot: string;
	runs: string;
	runGame?: boolean;
	signal?: AbortSignal;
}

interface CommandResult {
	exitCode: number | null;
	output: string;
	timedOut: boolean;
	error?: string;
}

async function runCommand(executable: string, args: string[], timeoutMs: number, signal?: AbortSignal): Promise<CommandResult> {
	return await new Promise((resolve) => {
		const child = spawn(executable, args, { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
		let output = "";
		let timedOut = false;
		let error: string | undefined;
		const append = (data: Buffer) => { output += data.toString("utf8"); if (output.length > 2_000_000) output = output.slice(-2_000_000); };
		child.stdout.on("data", append);
		child.stderr.on("data", append);
		const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
		const abort = () => child.kill();
		signal?.addEventListener("abort", abort, { once: true });
		child.on("error", (cause: Error) => { error = cause.message; });
		child.on("close", (exitCode) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", abort);
			resolve({ exitCode, output, timedOut, error: signal?.aborted ? "Verification aborted" : error });
		});
	});
}

export function parseGodotErrors(output: string, stage: string): Failure[] {
	const errors: Failure[] = [];
	for (const line of output.split(/\r?\n/)) {
		if (!/(?:SCRIPT ERROR:|^ERROR:|Parse Error:|Parser Error:|Failed loading resource:)/i.test(line)) continue;
		const location = line.match(/(?:res:\/\/)?([^\s:]+\.(?:gd|tscn|tres|gdshader))(?::(\d+))?/i);
		const message = line.trim().slice(0, 400);
		if (!errors.some((error) => error.message === message)) {
			errors.push({ stage, message, file: location?.[1], line: location?.[2] ? Number(location[2]) : undefined });
		}
		if (errors.length >= 12) break;
	}
	return errors;
}

async function saveEvidence(runs: string, report: Verification, raw: string): Promise<Verification> {
	const folder = path.join(runs, `${new Date().toISOString().replaceAll(":", "-")}-${randomUUID().slice(0, 8)}`);
	await fs.mkdir(folder, { recursive: true });
	await fs.writeFile(path.join(folder, "godot.log"), raw, "utf8");
	const saved = { ...report, evidence: path.join(folder, "report.json") };
	await fs.writeFile(saved.evidence, JSON.stringify(saved, null, 2), "utf8");
	return saved;
}

export async function verifyProject(options: VerifyOptions): Promise<Verification> {
	const index = await inspectProject(options.project);
	const base: Verification = { status: "fail", stage: "structure", errors: [], score: 0, fingerprint: index.fingerprint, evidence: "" };
	if (!index.scenes.length || !index.mainScene) {
		base.errors = [{ stage: "structure", message: !index.scenes.length ? "No .tscn scene found." : "project.godot has no run/main_scene." }];
		return saveEvidence(options.runs, base, "Structural validation failed before Godot execution.\n");
	}
	try {
		await fs.access(options.godot);
	} catch {
		return saveEvidence(options.runs, { ...base, status: "infrastructure", stage: "godot", errors: [{ stage: "godot", message: `Godot executable not found: ${options.godot}` }] }, "Godot executable missing.\n");
	}
	const temp = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-verify-"));
	let raw = "";
	try {
		const sandbox = path.join(temp, "project");
		await fs.cp(options.project, sandbox, {
			recursive: true,
			filter: async (source) => {
				const relative = path.relative(options.project, source);
				if (relative.split(path.sep).some((part) => EXCLUDED.has(part))) return false;
				return !(await fs.lstat(source)).isSymbolicLink();
			},
		});
		const editor = await runCommand(options.godot, ["--headless", "--path", sandbox, "--editor", "--quit"], 60_000, options.signal);
		raw += `=== import ===\n${editor.output}\n`;
		if (editor.error || editor.timedOut) {
			return saveEvidence(options.runs, { ...base, status: "infrastructure", stage: "import", errors: [{ stage: "import", message: editor.error ?? "Godot import timed out." }] }, raw);
		}
		const importErrors = parseGodotErrors(editor.output, "import");
		if (editor.exitCode !== 0 || importErrors.length) {
			return saveEvidence(options.runs, { ...base, stage: "import", errors: importErrors.length ? importErrors : [{ stage: "import", message: `Godot exited with code ${editor.exitCode}.` }] }, raw);
		}
		base.score = 5;
		if (options.runGame !== false) {
			const game = await runCommand(options.godot, ["--headless", "--path", sandbox, "--quit-after", "60"], 25_000, options.signal);
			raw += `=== runtime ===\n${game.output}\n`;
			if (game.error || game.timedOut) {
				return saveEvidence(options.runs, { ...base, status: "infrastructure", stage: "runtime", errors: [{ stage: "runtime", message: game.error ?? "Godot runtime timed out." }] }, raw);
			}
			const runtimeErrors = parseGodotErrors(game.output, "runtime");
			if (game.exitCode !== 0 || runtimeErrors.length) {
				return saveEvidence(options.runs, { ...base, stage: "runtime", errors: runtimeErrors.length ? runtimeErrors : [{ stage: "runtime", message: `Godot exited with code ${game.exitCode}.` }] }, raw);
			}
		}
		return saveEvidence(options.runs, { ...base, status: "pass", stage: options.runGame === false ? "import" : "runtime", score: options.runGame === false ? 5 : 10 }, raw);
	} catch (error) {
		return saveEvidence(options.runs, { ...base, status: "infrastructure", stage: "copy", errors: [{ stage: "copy", message: error instanceof Error ? error.message : String(error) }] }, raw);
	} finally {
		await fs.rm(temp, { recursive: true, force: true });
	}
}
