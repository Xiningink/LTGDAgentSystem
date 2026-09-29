import { Type, type UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import path from "node:path";
import { acceptPlan, finishTask, generatorHandoff, newTask, recordCompletedSubtasks, recordVerification, type TaskState, type Verification } from "./controller.ts";
import { verifyProject } from "./godot.ts";
import { parsePlannerOutput, plannerInput, PLANNER_SYSTEM_PROMPT } from "./planner.ts";
import { inspectProject, inspectScene } from "./project.ts";

const workspace = path.resolve(import.meta.dirname, "../..");
const runs = path.join(workspace, "runs");
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

async function projectFingerprint(root: string): Promise<string> {
	return (await hasProjectFile(root)) ? (await inspectProject(root)).fingerprint : "";
}

function compact(result: Verification): string {
	const lines = [`Godot ${result.status.toUpperCase()} at ${result.stage}; score ${result.score}/10.`];
	for (const error of result.errors.slice(0, 6)) lines.push(`- ${error.file ?? error.stage}${error.line ? `:${error.line}` : ""}: ${error.message}`);
	if (result.errors.length > 6) lines.push(`${result.errors.length - 6} more distinct errors are in the verification report; the Planner receives all ${result.errors.length}.`);
	lines.push(`Evidence: ${result.evidence}`);
	if (result.status === "pass") lines.push("Import and headless boot passed. Gameplay and visual requirements still require review/playtesting.");
	return lines.join("\n");
}

function nextInstruction(state: TaskState): string {
	if (state.phase === "generate") return state.plan.length
		? `Implement the Planner handoff (objective: ${state.planObjective ?? state.goal.slice(0, 120)}; subtasks: ${state.plan.map((task) => task.id).join(", ")}). Finish the whole plan, then call godot_verify once.`
		: "Implement the request, then call godot_verify. A failure automatically invokes a short-context Planner.";
	if (state.phase === "review") return "Godot verification passed. Review the original requirements, then call godot_finish with concrete evidence; report any behavior that still needs human playtesting.";
	if (state.phase === "done") return "Give the user a concise final report with the verification evidence and remaining playtest limits.";
	if (state.phase === "stopped") return `Stop automatic retries and report the blocker: ${state.plannerError ?? "repeated identical failure or no progress"}.`;
	return "Planner is running; wait for its structured handoff.";
}

export default function godotPat(pi: ExtensionAPI): void {
	let state: TaskState | undefined;
	let initialFingerprint = "";
	let projectRoot = "";

	function persist(): void { if (state) pi.appendEntry("godot-pat-state", state); }
	function restore(entries: readonly unknown[]): void {
		state = undefined;
		for (const entry of entries) {
			if (typeof entry === "object" && entry !== null && "type" in entry && entry.type === "custom" && "customType" in entry && entry.customType === "godot-pat-state" && "data" in entry) {
				const loaded = entry.data as TaskState & { phase: string; schemaVersion?: number; plan?: (TaskState["plan"][number] & { targets?: string[] })[] };
				const legacyDone = loaded.schemaVersion === undefined && loaded.phase === "done" && !loaded.completionEvidence;
				state = {
					...loaded,
					schemaVersion: 3,
					phase: legacyDone ? "review" : ["direct", "repair", "execute_plan"].includes(loaded.phase) ? "generate" : loaded.phase as TaskState["phase"],
					plan: (loaded.plan ?? []).map((task) => ({
						id: task.id,
						problem: task.problem ?? "Continue the previously planned subtask.",
						goal: task.goal,
						suggested_files: task.suggested_files ?? (task as typeof task & { targets?: string[] }).targets,
					})),
					solved: loaded.solved ?? [],
				};
			}
		}
	}

	async function runPlanner(ctx: ExtensionContext, signal?: AbortSignal): Promise<string> {
		if (!state || state.phase !== "plan" || !projectRoot) throw new Error("A failed project verification is required before planning.");
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
				return generatorHandoff(state);
			} catch (error) {
				if (attempt === 1) throw error;
				correction = `\n\nYour previous JSON was rejected: ${error instanceof Error ? error.message : String(error)} Return one corrected JSON object.`;
			}
		}
		throw new Error("Planner did not produce a valid plan.");
	}

	async function verify(root: string, ctx: ExtensionContext, signal?: AbortSignal, completed: { id: string; evidence: string }[] = []): Promise<{ result: Verification; handoff: string }> {
		if (state?.phase === "done" || state?.phase === "stopped") throw new Error("This task has ended. Start a new task before verifying again.");
		if (state && completed.length) state = recordCompletedSubtasks(state, completed, await projectFingerprint(root));
		const result = await verifyProject({ project: root, godot, runs, signal });
		if (state) { state = recordVerification(state, result); persist(); }
		let handoff = result.status === "infrastructure" ? "Godot infrastructure failed. Report or resolve the environment error; this does not trigger planning." : state ? nextInstruction(state) : "";
		if (state?.phase === "plan") {
			try {
				handoff = await runPlanner(ctx, signal);
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				state = { ...state, phase: "stopped", plannerError: message };
				persist();
				handoff = nextInstruction(state);
			}
		}
		return { result, handoff };
	}

	pi.on("session_start", async (_event, ctx) => {
		restore(ctx.sessionManager.getBranch());
		projectRoot = state?.projectPath ?? ((await hasProjectFile(ctx.cwd)) ? path.resolve(ctx.cwd) : "");
		initialFingerprint = await projectFingerprint(projectRoot);
	});
	pi.on("session_tree", async (_event, ctx) => {
		restore(ctx.sessionManager.getBranch());
		projectRoot = state?.projectPath ?? ((await hasProjectFile(ctx.cwd)) ? path.resolve(ctx.cwd) : "");
		initialFingerprint = await projectFingerprint(projectRoot);
	});

	pi.on("input", async (event, ctx) => {
		if (event.source === "extension" || !event.text.trim()) return;
		projectRoot = "";
		state = newTask(event.text.trim());
		initialFingerprint = "";
		persist();
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!state && event.prompt.trim()) {
			projectRoot = "";
			state = newTask(event.prompt.trim());
			initialFingerprint = "";
			persist();
		}
		let restoredHandoff: string | undefined;
		if (state?.phase === "plan" && projectRoot) {
			try { restoredHandoff = await runPlanner(ctx, ctx.signal); }
			catch (error) {
				state = { ...state, phase: "stopped", plannerError: error instanceof Error ? error.message : String(error) };
				persist();
			}
		}
		return { message: restoredHandoff ? { customType: "godot-pat-plan", content: restoredHandoff, display: true } : undefined, systemPrompt: event.systemPrompt + `\n\nLTGD Godot workflow:
- You are the Generator. Keep Pi's current directory and use godot_set_project before editing. Use the user's output path if supplied; otherwise use game/ under the current directory.
- Use godot_inspect_project and godot_inspect_scene for concise context. Read raw files only for edits. Keep all project files inside the selected directory.
- After implementation, call godot_verify. On failure the extension automatically calls an isolated, short-context Planner and returns its complete plan. Implement the whole plan before verifying again; do not call a separate planning tool.
- A Godot pass proves import and headless boot only. Review the original requirements and call godot_finish before claiming completion.
- Do not modify shared assets/ or Godot_Engine/.` };
	});

	pi.on("context_with_system", (event) => {
		const active = state;
		if (!active) return;
		let updated = false;
		return { messages: event.messages.map((message) => {
			if (updated || message.role !== "system") return message;
			updated = true;
			const current = `Phase: ${active.phase}. Project: ${active.projectPath ?? "not selected"}. Goal: ${active.goal.slice(0, 1000)}.\n${nextInstruction(active)}`;
			return { ...message, sections: { ...message.sections, "ltgd-current-state": `<ltgd-current-state>\n${current}\n</ltgd-current-state>` } };
		}) };
	});

	pi.on("tool_call", (event) => {
		if (!state?.projectPath && ["write", "edit", "bash", "powershell"].includes(event.toolName)) {
			return { block: true, reason: "Select the project with godot_set_project before editing. Omit its path to use ./game, or pass the user's output path." };
		}
		if ((state?.phase === "plan" || state?.phase === "stopped") && ["write", "edit", "bash", "powershell"].includes(event.toolName)) {
			return { block: true, reason: "Generation is paused. Report the Planner blocker or wait for the structured plan." };
		}
	});

	pi.registerTool({
		name: "godot_set_project", label: "Select Godot project",
		description: "Select the user's output directory, or omit project to create game/ under Pi's current directory. All Godot checks use this directory.",
		parameters: Type.Object({ project: Type.Optional(Type.String({ description: "User-specified project or output directory; relative paths start from Pi's current directory" })) }),
		executionMode: "sequential",
		async execute(_id, params, _signal, _update, ctx) {
			if (!state) throw new Error("No active task.");
			if (state.phase !== "generate" || state.attempts > 0 || state.plan.length || state.solved.length) {
				throw new Error("Select the project before editing or verifying; start a new task to change projects later.");
			}
			const selected = path.resolve(ctx.cwd, params.project?.trim() || "game");
			await fs.mkdir(selected, { recursive: true });
			projectRoot = selected;
			initialFingerprint = await projectFingerprint(selected);
			state = { ...state, projectPath: selected, lastVerification: undefined };
			persist();
			return { content: [{ type: "text", text: `Selected Godot project: ${selected}. Create and edit project files there; all godot_* tools use this directory.` }], details: { project: selected } };
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
		name: "godot_verify", label: "Verify Godot project",
		description: "Import and boot a disposable project copy. On failure, automatically request a short-context plan. Optionally report completed planned subtasks in this same call.",
		parameters: Type.Object({ completed_subtasks: Type.Optional(Type.Array(Type.Object({ id: Type.String(), evidence: Type.String() }))) }), executionMode: "sequential",
		async execute(_id, params, signal, _update, ctx) {
			if (!(await hasProjectFile(projectRoot))) throw new Error(`No project.godot in ${projectRoot || "a selected directory"}. Select or create the project first.`);
			const { result, handoff } = await verify(projectRoot, ctx, signal, params.completed_subtasks ?? []);
			return { content: [{ type: "text", text: `${compact(result)}\n${handoff}` }], details: result };
		},
	});

	pi.registerTool({
		name: "godot_get_errors", label: "Last Godot errors",
		description: "Return the last compact verification result without running Godot again.",
		parameters: Type.Object({}),
		async execute() {
			return { content: [{ type: "text", text: state?.lastVerification ? compact(state.lastVerification) : "No verification has run in this task." }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_finish", label: "Complete verified game task",
		description: "Finish only after the current project passes Godot verification and the original requirements have concrete review evidence.",
		executionMode: "sequential",
		parameters: Type.Object({ evidence: Type.Array(Type.String(), { description: "Concrete evidence from review of the original requirements" }) }),
		async execute(_id, params) {
			if (!state || !projectRoot) throw new Error("Select an active project first.");
			const current = await inspectProject(projectRoot);
			state = finishTask(state, params.evidence, current.fingerprint);
			persist();
			return { content: [{ type: "text", text: "Task recorded as done. Report the implemented behavior, verification evidence, and any gameplay or visual checks that still need human playtesting." }], details: {} };
		},
	});

	pi.registerCommand("godot-status", {
		description: "Show the Godot-PaT task phase and latest verification",
		handler: async (_args, ctx) => ctx.ui.notify(state ? `${state.phase}; project ${projectRoot || "not selected"}; ${state.attempts} verification attempts.\n${state.lastVerification ? compact(state.lastVerification) : "No verification yet."}` : "No active task.", "info"),
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (!state || state.phase === "done" || state.phase === "stopped" || !projectRoot) return;
		if (state.phase === "generate" && state.plan.length) return;
		if (!(await hasProjectFile(projectRoot))) return;
		const current = await inspectProject(projectRoot);
		if (current.fingerprint === initialFingerprint || current.fingerprint === state.lastVerification?.fingerprint) return;
		const { result, handoff } = await verify(projectRoot, ctx);
		if (result.status === "fail" || result.status === "pass") {
			pi.sendMessage({ customType: "godot-pat-feedback", content: `${compact(result)}\n${handoff}`, display: true }, { triggerTurn: true, deliverAs: "followUp" });
		} else {
			pi.sendMessage({ customType: "godot-pat-feedback", content: compact(result), display: true }, { triggerTurn: false });
		}
	});
}
