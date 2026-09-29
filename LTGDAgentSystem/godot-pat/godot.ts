import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { TextDecoder } from "node:util";
import type { Failure, Verification } from "./controller.ts";
import { inspectProject } from "./project.ts";

const EXCLUDED = new Set([".git", ".godot", ".pi", ".pi-godot", "node_modules"]);

export interface VerifyOptions {
	project: string;
	godot: string;
	runGame?: boolean;
	signal?: AbortSignal;
}

interface CommandResult {
	exitCode: number | null;
	errors: Failure[];
	outputTail: string;
	timedOut: boolean;
	error?: string;
}

function sourceLocation(line: string): { file?: string; line?: number } {
	const match = line.match(/res:\/\/(.+?\.(?:gd|tscn|tres|gdshader|cs))(?::(\d+))?/i)
		?? line.match(/(?:^|[\s(])([^\s():]+\.(?:gd|tscn|tres|gdshader|cs))(?::(\d+))?/i);
	return { file: match?.[1], line: match?.[2] ? Number(match[2]) : undefined };
}

function distinctErrors(errors: Failure[]): Failure[] {
	const seen = new Set<string>();
	return errors.filter((error) => {
		const key = JSON.stringify([error.stage, error.file, error.line, error.message]);
		if (seen.has(key)) return false;
		seen.add(key);
		return true;
	});
}

class ErrorCollector {
	private readonly errors: Failure[] = [];
	private readonly pending = new Map<string, string>();
	private readonly decoders = new Map<string, TextDecoder>();
	private readonly lastByChannel = new Map<string, Failure>();
	private readonly stage: string;
	constructor(stage: string) { this.stage = stage; }
	private line(value: string, channel: string): void {
		if (/(?:SCRIPT ERROR:|\bERROR:|Parse Error:|Parser Error:|Failed loading resource:)/i.test(value)) {
			const error = { stage: this.stage, message: value.trim(), ...sourceLocation(value) };
			this.errors.push(error);
			this.lastByChannel.set(channel, error);
		} else if (/^\s*at:\s*/i.test(value) && this.lastByChannel.has(channel)) {
			const last = this.lastByChannel.get(channel)!;
			const location = sourceLocation(value);
			if (location.file && !last.file) Object.assign(last, location);
		}
	}
	push(data: Buffer, channel: string): void {
		let decoder = this.decoders.get(channel);
		if (!decoder) { decoder = new TextDecoder(); this.decoders.set(channel, decoder); }
		const joined = (this.pending.get(channel) ?? "") + decoder.decode(data, { stream: true });
		const lines = joined.split(/\r?\n/);
		this.pending.set(channel, lines.pop() ?? "");
		for (const line of lines) this.line(line, channel);
	}
	finish(): Failure[] {
		for (const [channel, pending] of this.pending) this.line(pending + (this.decoders.get(channel)?.decode() ?? ""), channel);
		return distinctErrors(this.errors);
	}
}

async function runCommand(executable: string, args: string[], timeoutMs: number, stage: string, signal?: AbortSignal): Promise<CommandResult> {
	return await new Promise((resolve) => {
		const child = spawn(executable, args, { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
		const collector = new ErrorCollector(stage);
		let outputTail = "";
		let timedOut = false;
		let error: string | undefined;
		const append = (channel: string) => (data: Buffer) => {
			collector.push(data, channel);
			outputTail = (outputTail + data.toString("utf8")).slice(-8_000);
		};
		child.stdout.on("data", append("stdout"));
		child.stderr.on("data", append("stderr"));
		const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
		const abort = () => child.kill();
		signal?.addEventListener("abort", abort, { once: true });
		child.on("error", (cause: Error) => { error = cause.message; });
		child.on("close", (exitCode) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", abort);
			resolve({ exitCode, errors: collector.finish(), outputTail, timedOut, error: signal?.aborted ? "Verification aborted" : error });
		});
	});
}

export function parseGodotErrors(output: string, stage: string): Failure[] {
	const collector = new ErrorCollector(stage);
	collector.push(Buffer.from(output), "output");
	return collector.finish();
}

function exitFailure(stage: string, result: CommandResult): Failure {
	const detail = result.outputTail.trim();
	return { stage, message: `Godot exited with code ${result.exitCode}.${detail ? ` Final output (up to 8000 characters):\n${detail}` : ""}` };
}

export async function verifyProject(options: VerifyOptions): Promise<Verification> {
	const index = await inspectProject(options.project);
	const base: Verification = { status: "fail", stage: "structure", errors: [], score: 0, fingerprint: index.fingerprint };
	if (!index.scenes.length || !index.mainScene) {
		base.errors = [{ stage: "structure", message: !index.scenes.length ? "No .tscn scene found." : "project.godot has no run/main_scene." }];
		return base;
	}
	try {
		await fs.access(options.godot);
	} catch {
		return { ...base, status: "infrastructure", stage: "godot", errors: [{ stage: "godot", message: `Godot executable not found: ${options.godot}` }] };
	}
	const temp = await fs.mkdtemp(path.join(os.tmpdir(), "ltgd-verify-"));
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
		const editor = await runCommand(options.godot, ["--headless", "--path", sandbox, "--editor", "--quit"], 60_000, "import", options.signal);
		if (editor.error || editor.timedOut) {
			return { ...base, status: "infrastructure", stage: "import", errors: [{ stage: "import", message: editor.error ?? "Godot import timed out." }] };
		}
		const importErrors = editor.errors;
		if (editor.exitCode !== 0 || importErrors.length) {
			return { ...base, stage: "import", errors: importErrors.length ? importErrors : [exitFailure("import", editor)] };
		}
		base.score = 5;
		if (options.runGame !== false) {
			const game = await runCommand(options.godot, ["--headless", "--path", sandbox, "--quit-after", "60"], 25_000, "runtime", options.signal);
			if (game.error || game.timedOut) {
				return { ...base, status: "infrastructure", stage: "runtime", errors: [{ stage: "runtime", message: game.error ?? "Godot runtime timed out." }] };
			}
			const runtimeErrors = game.errors;
			if (game.exitCode !== 0 || runtimeErrors.length) {
				return { ...base, stage: "runtime", errors: runtimeErrors.length ? runtimeErrors : [exitFailure("runtime", game)] };
			}
		}
		return { ...base, status: "pass", stage: options.runGame === false ? "import" : "runtime", score: options.runGame === false ? 5 : 10 };
	} catch (error) {
		return { ...base, status: "infrastructure", stage: "copy", errors: [{ stage: "copy", message: error instanceof Error ? error.message : String(error) }] };
	} finally {
		await fs.rm(temp, { recursive: true, force: true });
	}
}
