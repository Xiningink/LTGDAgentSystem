import { promises as fs } from "node:fs";
import path from "node:path";
import type { Failure, RepairPlan, TaskState } from "./controller.ts";
import type { ProjectIndex } from "./project.ts";

export const PLANNER_SYSTEM_PROMPT = `You are the Planner for a Godot game development task. The Executor found either a Godot runtime/import failure or a concrete missing original requirement. Analyze only that latest failure and the supplied project evidence. You cannot run tools or edit files. Every subtask must address the observed failure; distinguish a supported diagnosis from a hypothesis. Preserve the original requirement and do not invent optional improvements.

Return one JSON object. If project files need revision, return {"decision":"revise","reason":"...","subtasks":[{"problem":"...","goal":"...","suggested_files":["res://...godot"]}]}. Subtasks must be ordered and nonempty; suggested_files is optional and only a hint. If the evidence does not support a project-code change, return {"decision":"cannot_resolve_in_project","reason":"...","evidence":["..."]} and no subtasks. Distinguish observed evidence from hypotheses. Do not prescribe exact patches or add checks or dependencies. Return JSON only.`;

interface CodeExcerpt {
	file: string;
	start_line: number;
	end_line: number;
	code: string;
}

function projectFile(root: string, file: string): { full: string; relative: string } | undefined {
	const relative = file.replace(/^res:\/\//, "").replaceAll("\\", "/");
	if (!relative || relative.startsWith("/") || /^[A-Za-z]:/.test(relative)) return;
	const full = path.resolve(root, relative);
	if (!full.startsWith(root + path.sep)) return;
	return { full, relative };
}

async function currentCode(root: string, errors: Failure[]): Promise<{ excerpts: CodeExcerpt[]; unavailable: { file: string; reason: string }[] }> {
	const realRoot = await fs.realpath(root);
	const grouped = new Map<string, { full: string; lines: number[] }>();
	const unavailable: { file: string; reason: string }[] = [];
	for (const error of errors) {
		if (!error.file) continue;
		const found = projectFile(root, error.file);
		if (!found) {
			unavailable.push({ file: error.file, reason: "Path is outside the selected project." });
			continue;
		}
		const entry = grouped.get(found.relative) ?? { full: found.full, lines: [] };
		if (error.line && Number.isInteger(error.line) && error.line > 0) entry.lines.push(error.line);
		grouped.set(found.relative, entry);
	}
	const excerpts: CodeExcerpt[] = [];
	for (const [file, entry] of grouped) {
		if (!entry.lines.length) {
			unavailable.push({ file, reason: "Verification did not provide a source line." });
			continue;
		}
		try {
			const realFile = await fs.realpath(entry.full);
			if (!realFile.startsWith(realRoot + path.sep)) throw new Error("File resolves outside the selected project.");
			const stat = await fs.lstat(entry.full);
			if (!stat.isFile() || stat.isSymbolicLink()) throw new Error("Not a regular project file.");
			const lines = (await fs.readFile(entry.full, "utf8")).split(/\r?\n/);
			const ranges = entry.lines.filter((line) => line <= lines.length).map((line) => {
				let start = Math.max(1, line - 12);
				const end = Math.min(lines.length, line + 12);
				const header = file.endsWith(".gd") ? /^\s*(?:static\s+)?func\s+/ : /^\s*\[[^\]]+\]/;
				for (let cursor = line - 1; cursor >= start; cursor--) {
					if (header.test(lines[cursor - 1])) { start = cursor; break; }
				}
				return { start, end };
			}).sort((a, b) => a.start - b.start);
			if (!ranges.length) {
				unavailable.push({ file, reason: "Verification source line is outside the current file." });
				continue;
			}
			const merged: { start: number; end: number }[] = [];
			for (const range of ranges) {
				const previous = merged.at(-1);
				if (previous && range.start <= previous.end + 1) previous.end = Math.max(previous.end, range.end);
				else merged.push({ ...range });
			}
			for (const range of merged) excerpts.push({
				file, start_line: range.start, end_line: range.end,
				code: lines.slice(range.start - 1, range.end).map((line, index) => `${range.start + index}: ${line}`).join("\n"),
			});
		} catch (error) {
			unavailable.push({ file, reason: error instanceof Error ? error.message : String(error) });
		}
	}
	return { excerpts, unavailable };
}

export async function plannerInput(state: TaskState, project: ProjectIndex): Promise<string> {
	const failure = state.lastVerification;
	if (failure?.status === "pass" && state.reviewFailure) {
		return JSON.stringify({
			original_requirement: state.goal,
			project_overview: { main_scene: project.mainScene ?? null, scenes: project.scenes, scripts: project.scripts, total_files: project.resources },
			latest_requirement_failure: state.reviewFailure,
		});
	}
	if (failure?.status !== "fail") throw new Error("Planner requires a failed Executor check.");
	const { excerpts, unavailable } = await currentCode(project.project, failure.errors);
	return JSON.stringify({
		original_requirement: state.goal,
		project_overview: {
			main_scene: project.mainScene ?? null,
			total_files: project.resources,
			error_files: [...new Set(failure.errors.map((error) => error.file).filter((file): file is string => !!file))],
		},
		latest_failure: { stage: failure.stage, errors: failure.errors },
		current_code: excerpts,
		code_unavailable: unavailable,
	});
}

export function parsePlannerOutput(raw: string): RepairPlan {
	const trimmed = raw.trim();
	const fenced = trimmed.match(/^```(?:json)?\s*\r?\n([\s\S]*?)\r?\n```$/i);
	const source = fenced ? fenced[1].trim() : trimmed;
	if (!source) throw new Error("Planner response is empty.");
	let parsed: unknown;
	try { parsed = JSON.parse(source); }
	catch { throw new Error("Planner must return one valid JSON object."); }
	if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error("Planner must return one JSON object.");
	return parsed as RepairPlan;
}
