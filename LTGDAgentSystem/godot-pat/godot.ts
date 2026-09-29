import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createWriteStream, type WriteStream } from "node:fs";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { finished } from "node:stream/promises";
import { TextDecoder } from "node:util";
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
	errors: Failure[];
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

async function runCommand(executable: string, args: string[], timeoutMs: number, log: WriteStream, stage: string, signal?: AbortSignal): Promise<CommandResult> {
	return await new Promise((resolve) => {
		const child = spawn(executable, args, { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
		const collector = new ErrorCollector(stage);
		let timedOut = false;
		let error: string | undefined;
		const append = (channel: string, stream: typeof child.stdout) => (data: Buffer) => {
			if (!log.write(data)) { stream.pause(); log.once("drain", () => stream.resume()); }
			collector.push(data, channel);
		};
		child.stdout.on("data", append("stdout", child.stdout));
		child.stderr.on("data", append("stderr", child.stderr));
		const timer = setTimeout(() => { timedOut = true; child.kill(); }, timeoutMs);
		const abort = () => child.kill();
		signal?.addEventListener("abort", abort, { once: true });
		child.on("error", (cause: Error) => { error = cause.message; });
		child.on("close", (exitCode) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", abort);
			resolve({ exitCode, errors: collector.finish(), timedOut, error: signal?.aborted ? "Verification aborted" : error });
		});
	});
}

export function parseGodotErrors(output: string, stage: string): Failure[] {
	const collector = new ErrorCollector(stage);
	collector.push(Buffer.from(output), "output");
	return collector.finish();
}

async function saveEvidence(folder: string, report: Verification, log: WriteStream): Promise<Verification> {
	log.end();
	await finished(log);
	const saved = { ...report, evidence: path.join(folder, "report.json") };
	await fs.writeFile(saved.evidence, JSON.stringify(saved, null, 2), "utf8");
	return saved;
}

export async function verifyProject(options: VerifyOptions): Promise<Verification> {
	const index = await inspectProject(options.project);
	const base: Verification = { status: "fail", stage: "structure", errors: [], score: 0, fingerprint: index.fingerprint, evidence: "" };
	const folder = path.join(options.runs, `${new Date().toISOString().replaceAll(":", "-")}-${randomUUID().slice(0, 8)}`);
	await fs.mkdir(folder, { recursive: true });
	const log = createWriteStream(path.join(folder, "godot.log"));
	if (!index.scenes.length || !index.mainScene) {
		base.errors = [{ stage: "structure", message: !index.scenes.length ? "No .tscn scene found." : "project.godot has no run/main_scene." }];
		log.write("Structural validation failed before Godot execution.\n");
		return saveEvidence(folder, base, log);
	}
	try {
		await fs.access(options.godot);
	} catch {
		log.write("Godot executable missing.\n");
		return saveEvidence(folder, { ...base, status: "infrastructure", stage: "godot", errors: [{ stage: "godot", message: `Godot executable not found: ${options.godot}` }] }, log);
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
		log.write("=== import ===\n");
		const editor = await runCommand(options.godot, ["--headless", "--path", sandbox, "--editor", "--quit"], 60_000, log, "import", options.signal);
		if (editor.error || editor.timedOut) {
			return saveEvidence(folder, { ...base, status: "infrastructure", stage: "import", errors: [{ stage: "import", message: editor.error ?? "Godot import timed out." }] }, log);
		}
		const importErrors = editor.errors;
		if (editor.exitCode !== 0 || importErrors.length) {
			return saveEvidence(folder, { ...base, stage: "import", errors: importErrors.length ? importErrors : [{ stage: "import", message: `Godot exited with code ${editor.exitCode}; see godot.log for details.` }] }, log);
		}
		base.score = 5;
		if (options.runGame !== false) {
			log.write("\n=== runtime ===\n");
			const game = await runCommand(options.godot, ["--headless", "--path", sandbox, "--quit-after", "60"], 25_000, log, "runtime", options.signal);
			if (game.error || game.timedOut) {
				return saveEvidence(folder, { ...base, status: "infrastructure", stage: "runtime", errors: [{ stage: "runtime", message: game.error ?? "Godot runtime timed out." }] }, log);
			}
			const runtimeErrors = game.errors;
			if (game.exitCode !== 0 || runtimeErrors.length) {
				return saveEvidence(folder, { ...base, stage: "runtime", errors: runtimeErrors.length ? runtimeErrors : [{ stage: "runtime", message: `Godot exited with code ${game.exitCode}; see godot.log for details.` }] }, log);
			}
		}
		return saveEvidence(folder, { ...base, status: "pass", stage: options.runGame === false ? "import" : "runtime", score: options.runGame === false ? 5 : 10 }, log);
	} catch (error) {
		return saveEvidence(folder, { ...base, status: "infrastructure", stage: "copy", errors: [{ stage: "copy", message: error instanceof Error ? error.message : String(error) }] }, log);
	} finally {
		await fs.rm(temp, { recursive: true, force: true });
	}
}
