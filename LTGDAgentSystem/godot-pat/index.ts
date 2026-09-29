import { Type, type UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import path from "node:path";
import { acceptPlan, finishTask, generatorHandoff, newTask, recordVerification, type TaskState, type Verification } from "./controller.ts";
import { parseReviewOutput, reviewInput, REVIEW_SYSTEM_PROMPT } from "./executor.ts";
import { verifyProject } from "./godot.ts";
import { parsePlannerOutput, plannerInput, PLANNER_SYSTEM_PROMPT } from "./planner.ts";
import { inspectProject, inspectScene } from "./project.ts";

const workspace = path.resolve(import.meta.dirname, "../..");
const godot = path.join(workspace, "Godot_Engine", "Godot_v4.6.2-stable_win64_console.exe");

async function hasProjectFile(root: string): Promise<boolean> {
	if (!root) return false;
	try {
		return (await fs.stat(path.join(root, "project.godot"))).isFile();
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
		throw error;
	}
}

function handoffPath(text: string): string | undefined {
	return [...text.matchAll(/<ltgd-project-path>([^\r\n<>]+)<\/ltgd-project-path>/g)].at(-1)?.[1].trim();
}

function compact(result: Verification): string {
	const lines = [`Godot ${result.status.toUpperCase()} at ${result.stage}.`];
	for (const error of result.errors.slice(0, 6)) lines.push(`- ${error.file ?? error.stage}${error.line ? `:${error.line}` : ""}: ${error.message}`);
	if (result.errors.length > 6) lines.push(`${result.errors.length - 6} more distinct errors are in this verification result; the Planner receives all ${result.errors.length}.`);
	if (result.warnings?.length) lines.push(`${result.warnings.length} non-blocking Godot shutdown diagnostic(s): ${result.warnings[0].message}`);
	return lines.join("\n");
}

function nextInstruction(state: TaskState): string {
	if (state.phase === "generate") return `${state.plan?.length ? generatorHandoff(state) : "Implement the original game request directly. When the first complete implementation is in the project, end this Generator turn so the Executor can check it. Do not start a self-review or polish cycle."} End your final reply with <ltgd-project-path>the actual Godot project directory</ltgd-project-path>.`;
	if (state.phase === "review") return "The Executor is independently reviewing the original requirements. Wait for its result.";
	if (state.phase === "done") return "Give the user a concise final report with the verification and requirement review evidence.";
	if (state.phase === "stopped") return `Stop automatic retries and report the blocker: ${state.stopReason ?? "Executor could not proceed"}.`;
	return "The Executor is asking the Planner to repair a confirmed failure. Wait for its structured handoff.";
}

export default function godotPat(pi: ExtensionAPI): void {
	let state: TaskState | undefined;
	let projectRoot = "";
	let inputRevision = 0;
	let selectedInputRevision = 0;

	function persist(): void { if (state) pi.appendEntry("godot-pat-state", state); }
	function restore(entries: readonly unknown[]): void {
		state = undefined;
		for (const entry of entries) {
			if (typeof entry === "object" && entry !== null && "type" in entry && entry.type === "custom" && "customType" in entry && entry.customType === "godot-pat-state" && "data" in entry) {
				const loaded = entry.data as Omit<Partial<TaskState>, "completionEvidence"> & {
					completionEvidence?: string | { status: string; evidence: string }[];
					lastReviewFailureFingerprint?: string;
					plannerError?: string;
				};
				if (typeof loaded.goal !== "string" || !["generate", "plan", "review", "done", "stopped"].includes(loaded.phase ?? "")) continue;
				const phase = loaded.phase as TaskState["phase"];
				const oldChecks = Array.isArray(loaded.completionEvidence) ? loaded.completionEvidence : [];
				const completionEvidence = typeof loaded.completionEvidence === "string" ? loaded.completionEvidence : oldChecks.filter((check) => check.status === "implemented").map((check) => check.evidence).join("; ");
				state = {
					goal: loaded.goal,
					projectPath: loaded.projectPath,
					phase: phase === "done" && !completionEvidence ? "review" : phase,
					lastVerification: loaded.lastVerification,
					failureFingerprint: loaded.failureFingerprint ?? loaded.lastReviewFailureFingerprint ?? (loaded.phase === "generate" && loaded.plan?.length ? loaded.lastVerification?.fingerprint : undefined),
					reviewFailure: loaded.reviewFailure ?? (oldChecks.filter((check) => check.status === "missing").map((check) => check.evidence).join("; ") || undefined),
					plan: loaded.plan,
					completionEvidence: completionEvidence || undefined,
					stopReason: loaded.stopReason ?? loaded.plannerError,
				};
			}
		}
	}
	async function bindProject(cwd: string, declaredPath?: string): Promise<void> {
		if (!state) throw new Error("No active LTGD game task.");
		if (!declaredPath && !projectRoot) throw new Error("Generator did not provide a <ltgd-project-path> directory handoff.");
		const root = path.resolve(cwd, declaredPath ?? projectRoot);
		for (const shared of ["assets", "Godot_Engine"]) {
			const protectedRoot = path.join(workspace, shared);
			if (root === protectedRoot || root.startsWith(protectedRoot + path.sep)) throw new Error(`Godot project cannot be under shared ${shared}/: ${root}`);
		}
		if (!(await hasProjectFile(root))) throw new Error(`No project.godot at Generator handoff path: ${root}`);
		if (projectRoot === root && state.projectPath === root) return;
		projectRoot = root;
		state = { ...state, projectPath: projectRoot };
		persist();
	}

	async function runPlanner(ctx: ExtensionContext, signal?: AbortSignal): Promise<string> {
		if (!state || state.phase !== "plan" || !projectRoot) throw new Error("A failed Executor check is required before planning.");
		if (!ctx.model) throw new Error("No model is selected for the Planner.");
		const overview = await inspectProject(projectRoot);
		const input = await plannerInput(state, overview);
		let correction = "";
		for (let attempt = 0; attempt < 2; attempt++) {
			const request: UserMessage = { role: "user", content: [{ type: "text", text: input + correction }], timestamp: Date.now() };
			const response = await ctx.modelRegistry.streamSimple(
				ctx.model,
				{ systemPrompt: PLANNER_SYSTEM_PROMPT, messages: [request] },
				{ signal, reasoning: ctx.thinkingLevel === "off" ? undefined : ctx.thinkingLevel },
			).result();
			if (response.stopReason !== "stop") throw new Error(`Planner request ended with ${response.stopReason}${response.errorMessage ? `: ${response.errorMessage}` : ""}.`);
			try {
				const raw = response.content.filter((part): part is { type: "text"; text: string } => part.type === "text").map((part) => part.text).join("\n");
				state = acceptPlan(state, parsePlannerOutput(raw));
				persist();
				return state.phase === "stopped" ? nextInstruction(state) : generatorHandoff(state);
			} catch (error) {
				if (attempt === 1) throw error;
				correction = `\n\nYour previous JSON was rejected: ${error instanceof Error ? error.message : String(error)} Return one corrected JSON object.`;
			}
		}
		throw new Error("Planner did not produce a valid plan.");
	}

	async function runRequirementReview(ctx: ExtensionContext, signal?: AbortSignal): Promise<string> {
		if (!state || state.phase !== "review" || !projectRoot) throw new Error("A current Godot PASS is required before requirement review.");
		if (!ctx.model) throw new Error("No model is selected for the Executor review.");
		const project = await inspectProject(projectRoot);
		const input = await reviewInput(state, project, ctx.cwd);
		let correction = "";
		for (let attempt = 0; attempt < 2; attempt++) {
			const request: UserMessage = { role: "user", content: [{ type: "text", text: input + correction }], timestamp: Date.now() };
			const response = await ctx.modelRegistry.streamSimple(
				ctx.model,
				{ systemPrompt: REVIEW_SYSTEM_PROMPT, messages: [request] },
				{ signal, reasoning: ctx.thinkingLevel === "off" ? undefined : ctx.thinkingLevel },
			).result();
			if (response.stopReason !== "stop") throw new Error(`Executor review ended with ${response.stopReason}${response.errorMessage ? `: ${response.errorMessage}` : ""}.`);
			const current = await inspectProject(projectRoot);
			if (current.fingerprint !== project.fingerprint) throw new Error("Project changed during Executor review; re-run Godot verification.");
			try {
				const raw = response.content.filter((part): part is { type: "text"; text: string } => part.type === "text").map((part) => part.text).join("\n");
				state = finishTask(state, parseReviewOutput(raw), current.fingerprint);
				persist();
				return state.phase === "done" ? "Executor review PASS: the original game request is satisfied. Task recorded as done." : `Executor review found a missing original requirement: ${state.reviewFailure}.`;
			} catch (error) {
				if (attempt === 1) throw error;
				correction = `\n\nYour previous JSON was rejected: ${error instanceof Error ? error.message : String(error)} Return one corrected JSON object.`;
			}
		}
		throw new Error("Executor did not produce a valid requirement review.");
	}

	async function runExecutor(ctx: ExtensionContext, signal?: AbortSignal, declaredPath?: string): Promise<string> {
		if (!state) throw new Error("No active LTGD game task.");
		const messages: string[] = [];
		try {
			await bindProject(ctx.cwd, declaredPath);
			if (state.phase === "generate") {
				if (state.plan?.length && state.failureFingerprint && (await inspectProject(projectRoot)).fingerprint === state.failureFingerprint) {
					throw new Error("The project has not changed since the last failed Executor check. Stop instead of repeating it.");
				}
				const result = await verifyProject({ project: projectRoot, godot, signal });
				state = recordVerification(state, result);
				persist();
				messages.push(compact(result));
				if (state.phase === "stopped") messages.push(nextInstruction(state));
			}
			if (state.phase === "review") messages.push(await runRequirementReview(ctx, signal));
			if (state.phase === "plan") messages.push(await runPlanner(ctx, signal));
		} catch (error) {
			state = { ...state, phase: "stopped", stopReason: error instanceof Error ? error.message : String(error) };
			persist();
			messages.push(nextInstruction(state));
		}
		return messages.join("\n\n");
	}

	pi.on("session_start", (_event, ctx) => {
		restore(ctx.sessionManager.getBranch());
		projectRoot = state?.projectPath ?? "";
		selectedInputRevision = inputRevision;
	});
	pi.on("session_tree", (_event, ctx) => {
		restore(ctx.sessionManager.getBranch());
		projectRoot = state?.projectPath ?? "";
		selectedInputRevision = inputRevision;
	});

	pi.on("input", (event) => {
		if (event.source === "extension" || !event.text.trim()) return;
		inputRevision++;
	});

	pi.on("agent_before_settle", async (event, ctx) => {
		if (event.outcome !== "completed" || !state || !["generate", "review", "plan"].includes(state.phase)) return;
		const finalAssistant = [...(event.context?.contextMessages ?? [])].reverse().find((message) => message.role === "assistant");
		const finalText = finalAssistant?.role === "assistant" ? finalAssistant.content.filter((part) => part.type === "text").map((part) => part.text).join("\n") : "";
		const report = await runExecutor(ctx, ctx.signal, handoffPath(finalText));
		const continueGeneration = state?.phase === "generate";
		return {
			entries: [...event.entries, { type: "custom_message" as const, customType: "ltgd-executor", content: report, display: true }],
			continue: continueGeneration,
		};
	});

	pi.on("tool_call", (event) => {
		if (!state) return;
		if (inputRevision > selectedInputRevision && (state.phase === "done" || state.phase === "stopped")) return;
		if (state.phase === "review") {
			return { block: true, terminate: true, reason: "The Executor owns requirement review. Wait for its result." };
		}
		if (state.phase === "plan") {
			return { block: true, terminate: true, reason: "The Planner owns this confirmed failure. Wait for its structured repair plan." };
		}
		if (state.phase === "done" || state.phase === "stopped") {
			return { block: true, terminate: true, reason: "This LTGD task has ended. Report the result and wait for a new user request." };
		}
	});

	pi.on("before_agent_start", (event, ctx) => {
		if (!state && event.prompt.trim()) {
			state = newTask(event.prompt.trim());
			selectedInputRevision = inputRevision;
			persist();
		}
		if (!state || state.phase === "done" || state.phase === "stopped") return;
		return { systemPrompt: event.systemPrompt + `\n\nYou are the Generator for the active LTGD game task:
- Work in the output directory requested by the user; otherwise create game/ under ${ctx.cwd}. Create project.godot there.
- Build the game from the user's original task immediately. Do not write an upfront plan, break the task into a long checklist, request a Planner, or create optional objectives. Make only the local implementation decisions needed to code.
- Implement the complete requested player flow in one focused pass. Read files and run Godot during development only to resolve a concrete implementation blocker. Do not start repeated screenshot, self-test, refactor, visual polish, or minor-issue cycles.
- A flaw you noticed yourself is not a new work item. Fix it now only if it prevents an explicit original requirement or the main player flow from working; otherwise stop and let the Executor review the project.
- After the requested implementation is present, STOP using tools and end this Generator turn. As the final line of your reply, write <ltgd-project-path>the actual Godot project directory</ltgd-project-path>, using its real path without quotes or backticks. The Executor uses exactly that directory for Godot import, boot, and independent requirement review. Do not call a verification or finish tool, and do not claim the whole task is done before the Executor reports.
- If the Executor returns a confirmed failure and a Planner handoff, implement only those repair subtasks, then end the turn again. Do not expand the plan into optional improvements.
- After the first handoff, godot_inspect_project and godot_inspect_scene can provide concise context for the bound project. Keep all project files inside the requested directory. Do not modify shared assets/ or Godot_Engine/.` };
	});

	pi.on("context_with_system", (event) => {
		const active = state;
		if (!active || active.phase === "done" || active.phase === "stopped") return;
		let updated = false;
		return { messages: event.messages.map((message) => {
			if (updated || message.role !== "system") return message;
			updated = true;
			const current = `Phase: ${active.phase}. Project: ${active.projectPath ?? "awaiting Generator path handoff"}. Goal: ${active.goal.slice(0, 1000)}.\n${nextInstruction(active)}`;
			return { ...message, sections: { ...message.sections, "ltgd-current-state": `<ltgd-current-state>\n${current}\n</ltgd-current-state>` } };
		}) };
	});

	pi.registerTool({
		name: "godot_inspect_project", label: "Inspect Godot project",
		description: "Return a compact index of the generated Godot project and its main scene.",
		parameters: Type.Object({}),
		async execute(_id, _params, _signal, _update, ctx) {
			try { await bindProject(ctx.cwd); }
			catch (error) { return { content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }], details: {} }; }
			const index = await inspectProject(projectRoot);
			return { content: [{ type: "text", text: JSON.stringify({ mainScene: index.mainScene, scenes: index.scenes.slice(0, 80), scripts: index.scripts.slice(0, 80), totalFiles: index.resources }) }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_inspect_scene", label: "Inspect Godot scene",
		description: "Summarize scene nodes, script references, and signal connections without layout noise.",
		parameters: Type.Object({ scene: Type.String({ description: "Project-relative .tscn path or res:// path" }) }),
		async execute(_id, params, _signal, _update, ctx) {
			try { await bindProject(ctx.cwd); }
			catch (error) { return { content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }], details: {} }; }
			const scene = await inspectScene(projectRoot, params.scene);
			return { content: [{ type: "text", text: JSON.stringify(scene) }], details: {} };
		},
	});

	pi.registerCommand("godot-status", {
		description: "Show the Godot-PaT task phase and latest verification",
		handler: async (_args, ctx) => ctx.ui.notify(state ? `${state.phase}; project ${projectRoot || "awaiting Generator output"}.\n${state.lastVerification ? compact(state.lastVerification) : "No verification yet."}` : "No active task.", "info"),
	});

}
