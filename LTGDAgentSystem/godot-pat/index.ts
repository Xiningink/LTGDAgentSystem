import { Type, type UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import path from "node:path";
import { acceptPlan, activeWorkset, finishTask, generatorHandoff, newTask, recordVerification, type TaskState, type Verification } from "./controller.ts";
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

function compact(result: Verification): string {
	const lines = [`Godot ${result.status.toUpperCase()} at ${result.stage}; score ${result.score}/10.`];
	for (const error of result.errors.slice(0, 6)) lines.push(`- ${error.file ?? error.stage}${error.line ? `:${error.line}` : ""}: ${error.message}`);
	if (result.errors.length > 6) lines.push(`${result.errors.length - 6} more distinct errors are in this verification result; the Planner receives all ${result.errors.length}.`);
	if (result.warnings?.length) lines.push(`${result.warnings.length} non-blocking Godot shutdown diagnostic(s): ${result.warnings[0].message}`);
	if (result.status === "pass") lines.push("Import and headless boot passed. Review the original game requirements before completion.");
	return lines.join("\n");
}

function completeErrors(result: Verification): string {
	return [`Godot ${result.status.toUpperCase()} at ${result.stage}; ${result.errors.length} distinct errors.`,
		...result.errors.map((error) => `- ${error.file ?? error.stage}${error.line ? `:${error.line}` : ""}: ${error.message}`),
		...(result.warnings?.length ? [`${result.warnings.length} non-blocking shutdown diagnostic(s):`, ...result.warnings.map((warning) => `- ${warning.message}`)] : []),
	].join("\n");
}

function nextInstruction(state: TaskState): string {
	if (state.phase === "generate") {
		const workset = activeWorkset(state);
		return `Current ${workset.source} workset: ${workset.items.map((item) => `${item.id}: ${item.goal.length > 160 ? `${item.goal.slice(0, 157)}...` : item.goal}`).join("; ")}. Implement the requested game directly. When the first complete implementation is in the project, END THIS TURN. The Executor automatically verifies and reviews it. Do not run a self-review or polish cycle before handing off.`;
	}
	if (state.phase === "review") return "The Executor is independently reviewing the original requirements. Wait for its result.";
	if (state.phase === "done") return "Give the user a concise final report with the verification and requirement review evidence.";
	if (state.phase === "stopped") return `Stop automatic retries and report the blocker: ${state.plannerError ?? "repeated identical failure"}.`;
	return "The Executor is asking the Planner to repair a confirmed failure. Wait for its structured handoff.";
}

export default function godotPat(pi: ExtensionAPI): void {
	let state: TaskState | undefined;
	let projectRoot = "";
	let latestUserRequest = "";
	let inputRevision = 0;
	let selectedInputRevision = 0;

	function persist(): void { if (state) pi.appendEntry("godot-pat-state", state); }
	function restore(entries: readonly unknown[]): void {
		state = undefined;
		for (const entry of entries) {
			if (typeof entry === "object" && entry !== null && "type" in entry && entry.type === "custom" && "customType" in entry && entry.customType === "godot-pat-state" && "data" in entry) {
				const loaded = entry.data as TaskState & { phase: string; schemaVersion?: number; plan?: (TaskState["plan"][number] & { targets?: string[] })[] };
				const legacyDone = loaded.schemaVersion === undefined && loaded.phase === "done" && !loaded.completionEvidence;
				const restored = { ...loaded } as TaskState & { solved?: unknown; integrationChecks?: unknown };
				delete restored.solved;
				delete restored.integrationChecks;
				state = {
					...restored,
					schemaVersion: 7,
					requirements: loaded.requirements?.length ? loaded.requirements : [{ id: "R1", text: loaded.goal }],
					phase: legacyDone ? "review" : ["direct", "repair", "execute_plan"].includes(loaded.phase) ? "generate" : loaded.phase as TaskState["phase"],
					plan: (loaded.plan ?? []).map((task) => ({
						id: task.id,
						problem: task.problem ?? "Continue the previously planned subtask.",
						goal: task.goal,
						suggested_files: task.suggested_files ?? (task as typeof task & { targets?: string[] }).targets,
					})),
				};
			}
		}
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
				return state.phase === "done" ? "Executor review PASS: every original requirement is satisfied. Task recorded as done." : `Executor review found missing original requirements: ${state.pendingRequirements?.join(", ")}.`;
			} catch (error) {
				if (attempt === 1) throw error;
				correction = `\n\nYour previous JSON was rejected: ${error instanceof Error ? error.message : String(error)} Return one corrected JSON object.`;
			}
		}
		throw new Error("Executor did not produce a valid requirement review.");
	}

	async function runExecutor(ctx: ExtensionContext, signal?: AbortSignal): Promise<string> {
		if (!state || !projectRoot) throw new Error("Select a Godot project first.");
		const messages: string[] = [];
		try {
			if (state.phase === "generate") {
				if (state.lastReviewFailureFingerprint && (await inspectProject(projectRoot)).fingerprint === state.lastReviewFailureFingerprint) {
					throw new Error("The Planner returned a requirement repair, but the project has not changed. Stop instead of repeating the same review.");
				}
				const result = await verifyProject({ project: projectRoot, godot, signal });
				state = recordVerification(state, result);
				persist();
				messages.push(compact(result));
				if (result.status === "infrastructure") throw new Error("Godot infrastructure failed; no project repair plan was requested.");
				if (state.phase === "stopped") messages.push(nextInstruction(state));
			}
			if (state.phase === "review") messages.push(await runRequirementReview(ctx, signal));
			if (state.phase === "plan") messages.push(await runPlanner(ctx, signal));
		} catch (error) {
			state = { ...state, phase: "stopped", plannerError: error instanceof Error ? error.message : String(error) };
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
		latestUserRequest = event.text.trim();
		inputRevision++;
	});

	pi.on("agent_before_settle", async (event, ctx) => {
		if (event.outcome !== "completed" || !state?.projectPath || !["generate", "review", "plan"].includes(state.phase)) return;
		const report = await runExecutor(ctx, ctx.signal);
		const continueGeneration = state?.phase === "generate";
		return {
			entries: [...event.entries, { type: "custom_message" as const, customType: "ltgd-executor", content: report, display: true }],
			continue: continueGeneration,
		};
	});

	pi.on("tool_call", (event) => {
		if (!state?.projectPath) return;
		if (inputRevision > selectedInputRevision && event.toolName === "godot_set_project") return;
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

	pi.on("before_agent_start", (event) => {
		if (event.prompt.trim() && (!state?.projectPath || state.phase === "done" || state.phase === "stopped")) latestUserRequest = event.prompt.trim();
		if (!state?.projectPath || state.phase === "done" || state.phase === "stopped") {
			return { systemPrompt: event.systemPrompt + "\n\nIf the user requests Godot game development with LTGD, call godot_set_project to activate the workflow. For other tasks, leave LTGD tools unused." };
		}
		return { systemPrompt: event.systemPrompt + `\n\nWhen working on the selected LTGD Godot game, follow this workflow; for unrelated requests, use Pi normally:
- You are the Generator. Keep Pi's current directory. The selected project is ${state.projectPath}.
- Build the game from the user's original task immediately. Do not write an upfront plan, break the task into a long checklist, request a Planner, or create optional objectives. Make only the local implementation decisions needed to code.
- Implement the complete requested player flow in one focused pass. Read files and run Godot during development only to resolve a concrete implementation blocker. Do not start repeated screenshot, self-test, refactor, visual polish, or minor-issue cycles.
- A flaw you noticed yourself is not a new work item. Fix it now only if it prevents an explicit original requirement or the main player flow from working; otherwise stop and let the Executor review the project.
- After the requested implementation is present, STOP using tools and end this Generator turn. The Executor automatically performs Godot import, boot, and independent requirement review. Do not call a verification or finish tool, and do not claim the whole task is done before the Executor reports.
- If the Executor returns a confirmed failure and a Planner handoff, implement only those repair subtasks, then end the turn again. Do not expand the plan into optional improvements.
- Use godot_inspect_project and godot_inspect_scene for concise context. Keep all project files inside the selected directory. Do not modify shared assets/ or Godot_Engine/.` };
	});

	pi.on("context_with_system", (event) => {
		const active = state;
		if (!active?.projectPath || active.phase === "done" || active.phase === "stopped") return;
		let updated = false;
		return { messages: event.messages.map((message) => {
			if (updated || message.role !== "system") return message;
			updated = true;
			const current = `Use this state only for the selected Godot game; ignore it for unrelated user requests.\nPhase: ${active.phase}. Project: ${active.projectPath}. Goal: ${active.goal.slice(0, 1000)}.\n${nextInstruction(active)}`;
			return { ...message, sections: { ...message.sections, "ltgd-current-state": `<ltgd-current-state>\n${current}\n</ltgd-current-state>` } };
		}) };
	});

	pi.registerTool({
		name: "godot_set_project", label: "Select Godot project",
		description: "Activate a Godot game task and select its output directory. Omit project to use game/ under Pi's current directory. Do not decompose the task before coding. Omit requirements unless the user supplied an explicit acceptance list; otherwise the full original goal is R1. Set new_task only after a new user request to start another game.",
		parameters: Type.Object({
			project: Type.Optional(Type.String({ description: "User-specified project or output directory; relative paths start from Pi's current directory" })),
			new_task: Type.Optional(Type.Boolean({ description: "Start a new Godot game task even if another project is active" })),
			requirements: Type.Optional(Type.Array(Type.Object({ id: Type.String(), text: Type.String() }), { description: "Only explicit user-supplied acceptance criteria; do not invent a detailed requirement breakdown" })),
		}),
		executionMode: "sequential",
		async execute(_id, params, _signal, _update, ctx) {
			if (state?.projectPath) {
				if (!params.new_task && state.phase === "generate" && state.attempts === 0 && !state.plan.length && !state.pendingRequirements?.length) {
					return { content: [{ type: "text", text: `Godot project already selected: ${state.projectPath}. Requirements remain fixed for this task.` }], details: { project: state.projectPath } };
				}
				if (!params.new_task) throw new Error("Use new_task after a new user request to start another Godot game task; current requirements cannot be replaced.");
				if (inputRevision <= selectedInputRevision) throw new Error("A new user request is required before starting another Godot game task.");
			}
			const selected = path.resolve(ctx.cwd, params.project?.trim() || "game");
			await fs.mkdir(selected, { recursive: true });
			projectRoot = selected;
			state = { ...newTask(latestUserRequest || "Godot game development task", params.requirements), projectPath: selected };
			selectedInputRevision = inputRevision;
			persist();
			return { content: [{ type: "text", text: `Selected Godot project: ${selected}. Requirements: ${state.requirements.map((item) => `${item.id}: ${item.text}`).join("; ")}. Create and edit project files there; all godot_* tools use this directory.` }], details: { project: selected } };
		},
	});

	pi.registerTool({
		name: "godot_inspect_project", label: "Inspect Godot project",
		description: "Return a compact index of the selected Godot project and its main scene.",
		parameters: Type.Object({}),
		async execute() {
			if (!(await hasProjectFile(projectRoot))) return { content: [{ type: "text", text: `No project.godot in ${projectRoot || "a selected directory"}. Call godot_set_project first, then create the project there.` }], details: {} };
			const index = await inspectProject(projectRoot);
			return { content: [{ type: "text", text: JSON.stringify({ mainScene: index.mainScene, scenes: index.scenes.slice(0, 80), scripts: index.scripts.slice(0, 80), totalFiles: index.resources }) }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_inspect_scene", label: "Inspect Godot scene",
		description: "Summarize scene nodes, script references, and signal connections without layout noise.",
		parameters: Type.Object({ scene: Type.String({ description: "Project-relative .tscn path or res:// path" }) }),
		async execute(_id, params) {
			if (!projectRoot) throw new Error("Select a project with godot_set_project first.");
			const scene = await inspectScene(projectRoot, params.scene);
			return { content: [{ type: "text", text: JSON.stringify(scene) }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_get_errors", label: "Last Godot errors",
		description: "Return all errors from the last Godot verification without running Godot again.",
		parameters: Type.Object({}),
		async execute() {
			return { content: [{ type: "text", text: state?.lastVerification ? completeErrors(state.lastVerification) : "No verification has run in this task." }], details: {} };
		},
	});

	pi.registerCommand("godot-status", {
		description: "Show the Godot-PaT task phase and latest verification",
		handler: async (_args, ctx) => ctx.ui.notify(state ? `${state.phase}; project ${projectRoot || "not selected"}; ${state.attempts} verification attempts.\n${state.lastVerification ? compact(state.lastVerification) : "No verification yet."}` : "No active task.", "info"),
	});

}
