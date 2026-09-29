import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import path from "node:path";
import { acceptPlan, completeSubtask, newTask, recordVerification, restoreTaskState, shouldContinueAfterVerification, type Subtask, type TaskState, type Verification } from "./controller.ts";
import { verifyProject } from "./godot.ts";
import { inspectProject, inspectScene, resolveProjectDirectory } from "./project.ts";

const workspace = path.resolve(import.meta.dirname, "../..");
const runs = path.join(workspace, "runs");
const godot = path.join(workspace, "Godot_Engine", "Godot_v4.6.2-stable_win64_console.exe");

async function hasProjectFile(root: string): Promise<boolean> {
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
	lines.push(`Evidence: ${result.evidence}`);
	if (result.status === "pass") lines.push("Import and headless boot passed. Gameplay and visual requirements still require review/playtesting.");
	return lines.join("\n");
}

function nextInstruction(state: TaskState): string {
	if (state.phase === "repair") return "Fix the listed failure with the smallest relevant change, then run godot_verify again.";
	if (state.phase === "plan") return "Quick repair failed. Call godot_plan with 1-6 short ordered subtasks before editing further.";
	if (state.phase === "stopped") return "Repeated failure or no progress: stop automatic retries and report the blocker to the user.";
	if (state.phase === "execute_plan") return state.lastVerification?.status === "pass"
		? `Review requirement behavior for ${state.plan[state.currentSubtask]?.goal ?? state.goal}; call godot_subtask_done with concrete evidence to advance.`
		: `Continue the current subtask: ${state.plan[state.currentSubtask]?.goal ?? state.goal}.`;
	return "";
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
				state = restoreTaskState(entry.data);
			}
		}
	}

	async function verify(root: string, signal?: AbortSignal): Promise<Verification> {
		const result = await verifyProject({ project: root, godot, runs, signal });
		if (state) { state = recordVerification(state, result); persist(); }
		return result;
	}

	pi.on("session_start", async (_event, ctx) => {
		restore(ctx.sessionManager.getBranch());
		projectRoot = state?.projectPath ?? path.resolve(ctx.cwd);
		initialFingerprint = await projectFingerprint(projectRoot);
	});
	pi.on("session_tree", async (_event, ctx) => {
		restore(ctx.sessionManager.getBranch());
		projectRoot = state?.projectPath ?? path.resolve(ctx.cwd);
		initialFingerprint = await projectFingerprint(projectRoot);
	});

	pi.on("input", async (event, ctx) => {
		if (event.source === "extension" || !event.text.trim()) return;
		const selectedProject = state?.projectPath;
		projectRoot = selectedProject ?? path.resolve(ctx.cwd);
		state = { ...newTask(event.text.trim()), ...(selectedProject ? { projectPath: selectedProject } : {}) };
		initialFingerprint = await projectFingerprint(projectRoot);
		persist();
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (!state && event.prompt.trim()) {
			projectRoot = path.resolve(ctx.cwd);
			state = newTask(event.prompt.trim());
			initialFingerprint = await projectFingerprint(projectRoot);
			persist();
		}
		const phase = state?.phase ?? "direct";
		const large = state ? state.goal.length > 180 || /(?:完整.*游戏|制作.*游戏|开发.*游戏|build.*game|create.*game)/i.test(state.goal) : false;
		const prompt = `\n\nLTGD Godot workflow (current phase: ${phase}):
- Keep Pi's current working directory. If the user specifies a project or delivery directory, build directly there and call godot_set_project with that path before editing; relative paths start from Pi's current directory. Otherwise, use the current directory as the project. Keep the user's Pi conversation as the entry point.
- ${large ? "This is a large task: make a short 3-7 item milestone sketch, then implement one milestone at a time." : "This is a local task: edit directly without a separate plan."}
- Use godot_inspect_project and godot_inspect_scene for concise context. Read raw files only for edits.
- Before claiming a game change is complete, call godot_verify. A passing check proves import and headless boot only; assess gameplay requirements separately.
- On first failure, repair the specific error. On a failed repair, call godot_plan before further edits. Stop at repeated unchanged failures.
- Do not modify the shared assets/ or Godot_Engine/ directories.
${state ? `Current goal: ${state.goal.slice(0, 500)}\n${nextInstruction(state)}` : ""}`;
		const solved = state?.solved?.length ? `\nPreviously checked subtasks: ${state.solved.slice(-6).map((item) => `${item.id}: ${item.evidence}`).join("; ")}` : "";
		return { systemPrompt: event.systemPrompt + prompt + solved };
	});

	pi.on("tool_call", (event) => {
		if (state?.phase === "plan" && ["write", "edit", "bash", "powershell"].includes(event.toolName)) {
			return { block: true, reason: "Planner phase is read-only. Call godot_plan with a concise ordered plan first." };
		}
	});

	pi.registerTool({
		name: "godot_set_project", label: "Select Godot project",
		description: "Select the user's specified Godot project or delivery directory for all LTGD inspection and verification. Relative paths resolve from Pi's working directory; this does not change Pi's working directory.",
		parameters: Type.Object({ project: Type.String({ description: "Project directory from the user's request, relative to Pi's working directory or absolute" }) }),
		executionMode: "sequential",
		async execute(_id, params, _signal, _update, ctx) {
			if (!state) throw new Error("No active task.");
			if (state.phase !== "direct" || state.attempts > 0 || state.plan.length || state.solved.length) {
				throw new Error("Select the project before editing or verifying; start a new task to change projects later.");
			}
			const selected = resolveProjectDirectory(ctx.cwd, params.project);
			initialFingerprint = await projectFingerprint(selected);
			projectRoot = selected;
			state = { ...state, projectPath: selected, lastVerification: undefined };
			persist();
			return { content: [{ type: "text", text: `Selected Godot project: ${selected}. Create and edit project files directly there; all godot_* tools now use this directory.` }], details: { project: selected } };
		},
	});

	pi.registerTool({
		name: "godot_inspect_project", label: "Inspect Godot project",
		description: "Return a compact index of the selected Godot project and its main scene.",
		parameters: Type.Object({}),
		async execute() {
			if (!(await hasProjectFile(projectRoot))) return { content: [{ type: "text", text: `No project.godot at ${projectRoot}. Create the project there or call godot_set_project with the user's requested directory.` }], details: {} };
			const index = await inspectProject(projectRoot);
			return { content: [{ type: "text", text: JSON.stringify({ mainScene: index.mainScene, scenes: index.scenes.slice(0, 80), scripts: index.scripts.slice(0, 80), totalFiles: index.resources }) }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_inspect_scene", label: "Inspect Godot scene",
		description: "Summarize scene nodes, script references, and signal connections without layout noise.",
		parameters: Type.Object({ scene: Type.String({ description: "Project-relative .tscn path or res:// path" }) }),
		async execute(_id, params) {
			const scene = await inspectScene(projectRoot, params.scene);
			return { content: [{ type: "text", text: JSON.stringify(scene) }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_verify", label: "Verify Godot project",
		description: "Import and boot a disposable project copy in headless Godot; return concise errors and evidence path.",
		parameters: Type.Object({}), executionMode: "sequential",
		async execute(_id, _params, signal) {
			if (!(await hasProjectFile(projectRoot))) throw new Error(`No project.godot at ${projectRoot}. Create the project or select its directory with godot_set_project.`);
			const result = await verify(projectRoot, signal);
			return { content: [{ type: "text", text: `${compact(result)}\n${state ? nextInstruction(state) : ""}` }], details: result };
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
		name: "godot_plan", label: "Plan after failed repair",
		description: "Record a compact ordered plan after direct trial and quick repair have both failed.",
		parameters: Type.Object({ subtasks: Type.Array(Type.Object({ id: Type.String(), goal: Type.String(), targets: Type.Array(Type.String()), depends_on: Type.Array(Type.String()) })) }),
		async execute(_id, params) {
			if (!state) throw new Error("No active task.");
			state = acceptPlan(state, params.subtasks as Subtask[]);
			persist();
			return { content: [{ type: "text", text: `Plan accepted. Start ${state.plan[0]?.id}: ${state.plan[0]?.goal}. Verify after implementing it.` }], details: {} };
		},
	});

	pi.registerTool({
		name: "godot_subtask_done", label: "Complete planned subtask",
		description: "Advance a planned subtask after successful Godot verification and a concrete requirement check.",
		parameters: Type.Object({ evidence: Type.String({ description: "Concise description of behavior checked" }) }),
		async execute(_id, params) {
			if (!state) throw new Error("No active task.");
			const current = await inspectProject(projectRoot);
			state = completeSubtask(state, params.evidence, current.fingerprint);
			persist();
			const next = state.plan[state.currentSubtask];
			return { content: [{ type: "text", text: next ? `Subtask recorded. Next: ${next.id} ${next.goal}` : "All planned subtasks recorded. Review the full game and report any unverified gameplay or visual requirements." }], details: {} };
		},
	});

	pi.registerCommand("godot-status", {
		description: "Show the Godot-PaT task phase and latest verification",
		handler: async (_args, ctx) => ctx.ui.notify(state ? `${state.phase}; project ${projectRoot}; ${state.attempts} verification attempts.\n${state.lastVerification ? compact(state.lastVerification) : "No verification yet."}` : "No active task.", "info"),
	});

	pi.on("turn_end", async (event) => {
		if (event.message.role !== "assistant") return;
		const usage = event.message.usage;
		if (!usage) return;
		await fs.mkdir(runs, { recursive: true });
		await fs.appendFile(path.join(runs, "usage.jsonl"), JSON.stringify({ at: new Date().toISOString(), phase: state?.phase, input: usage.input, output: usage.output, cacheRead: usage.cacheRead, cacheWrite: usage.cacheWrite, cost: usage.cost.total }) + "\n");
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (!state || state.phase === "done" || state.phase === "stopped" || !projectRoot) return;
		if (!(await hasProjectFile(projectRoot))) return;
		const current = await inspectProject(projectRoot);
		if (current.fingerprint === initialFingerprint || current.fingerprint === state.lastVerification?.fingerprint) return;
		const result = await verify(projectRoot);
		if (shouldContinueAfterVerification(state, result)) {
			pi.sendMessage({ customType: "godot-pat-feedback", content: `${compact(result)}\n${nextInstruction(state)}`, display: true }, { triggerTurn: true, deliverAs: "followUp" });
		} else {
			pi.sendMessage({ customType: "godot-pat-feedback", content: `${compact(result)}\n${nextInstruction(state)}`, display: true }, { triggerTurn: false });
		}
	});
}
