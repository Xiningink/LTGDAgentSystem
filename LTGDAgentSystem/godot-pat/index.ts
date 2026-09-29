import { Type, type UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import path from "node:path";
import { acceptPlan, activeWorkset, finishTask, generatorHandoff, migrateTaskState, newTask, recordVerification, validateWorksetChecks, type ActiveWorkset, type Requirement, type RequirementSource, type TaskState, type Verification, type WorksetCheck } from "./controller.ts";
import { CONTRACT_EXTRACTION_PROMPT, parseContractItems } from "./contract.ts";
import { verifyProject } from "./godot.ts";
import { parsePlannerOutput, plannerInput, PLANNER_SYSTEM_PROMPT } from "./planner.ts";
import { inspectProject, inspectScene } from "./project.ts";

const workspace = path.resolve(import.meta.dirname, "../..");
const godot = path.join(workspace, "Godot_Engine", "Godot_v4.6.2-stable_win64_console.exe");
const REVIEW_READ_TOOLS = new Set(["read", "grep", "find", "ls", "godot_inspect_project", "godot_inspect_scene", "godot_get_errors"]);

async function requirementSources(request: string, cwd: string, selected: string, filePaths: string[] = []): Promise<RequirementSource[]> {
	if (!request.trim()) throw new Error("A user task specification is required before selecting a Godot project.");
	const sources: RequirementSource[] = [{ id: "user_request", text: request }];
	const explicit = filePaths.map((file) => path.resolve(cwd, file));
	const mentioned = [...request.matchAll(/(?:^|[\s`"'(])([^\s`"'<>|?*()]+\.(?:md|txt|toml))(?=$|[\s`"',.;!?)])/gi)];
	const automatic = ["instruction.md", "task.toml"].flatMap((name) => [path.join(cwd, name), path.join(selected, name)]);
	const seen = new Set<string>();
	const referenced: string[] = [];
	for (const match of mentioned) {
		const name = match[1];
		const candidates = path.isAbsolute(name) ? [name] : [path.resolve(cwd, name), path.resolve(selected, name)];
		let found: string | undefined;
		for (const candidate of candidates) {
			try { if ((await fs.stat(candidate)).isFile()) { found = candidate; break; } }
			catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
		}
		if (!found) throw new Error(`Referenced task specification file was not found: ${name}`);
		referenced.push(found);
	}
	for (const file of [...explicit, ...referenced, ...automatic]) {
		const key = file.toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		let stat;
		try { stat = await fs.stat(file); }
		catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT" && automatic.includes(file) && !explicit.includes(file) && !referenced.includes(file)) continue;
			throw new Error(`Cannot read task specification file ${file}: ${error instanceof Error ? error.message : String(error)}`);
		}
		if (!stat.isFile() || stat.size > 512_000) throw new Error(`Task specification must be a readable text file under 512 KB: ${file}`);
		sources.push({ id: `file:${file}`, text: await fs.readFile(file, "utf8") });
	}
	return sources;
}

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
	if (result.errors.length > 6) lines.push(`${result.errors.length - 6} more distinct errors are in this verification result; the Planner receives all ${result.errors.length}.`);
	if (result.warnings?.length) lines.push(`${result.warnings.length} non-blocking Godot shutdown diagnostic(s): ${result.warnings[0].message}`);
	if (result.status === "pass") lines.push("Import and headless boot passed. Gameplay and visual requirements still require review/playtesting.");
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
		return `Current ${workset.source} workset: ${workset.items.map((item) => `${item.id}: ${item.goal.length > 160 ? `${item.goal.slice(0, 157)}...` : item.goal}`).join("; ")}. Complete only the unmet items. When this whole workset is complete, call godot_verify with one evidence-backed workset_checks entry per ID. Do not continue exploring for optional improvements.`;
	}
	if (state.phase === "review") return `Godot import and boot passed. Review the original requirements (${state.requirements.map((item) => `${item.id}: ${item.text}`).join("; ")}). Call godot_finish once with evidence for each ID. A missing requirement directly returns to generation. Use needs_playtest for behavior that exists but needs a human test. Do not edit the project or seek optional improvements.`;
	if (state.phase === "done") return "Give the user a concise final report with the verification evidence and remaining playtest limits.";
	if (state.phase === "stopped") return `Stop automatic retries and report the blocker: ${state.plannerError ?? "repeated identical failure"}.`;
	return "Planner is running; wait for its structured handoff.";
}

function incompleteWorksetMessage(workset: ActiveWorkset, unresolved: WorksetCheck[]): string {
	return `Current ${workset.source} workset is incomplete. Godot verification was not run.\nUnresolved:\n${unresolved.map((check) => `- ${check.id}: ${workset.items.find((item) => item.id === check.id)?.goal} — ${check.evidence}`).join("\n")}\nContinue only the unresolved workset items. Do not add optional improvements.`;
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
				const loaded = entry.data as Partial<TaskState> & { goal: string; phase?: string; schemaVersion?: number };
				state = migrateTaskState(loaded);
			}
		}
	}

	async function modelText(ctx: ExtensionContext, systemPrompt: string, input: string, signal?: AbortSignal): Promise<string> {
		if (!ctx.model) throw new Error("No model is selected for Controller review.");
		const request: UserMessage = { role: "user", content: [{ type: "text", text: input }], timestamp: Date.now() };
		const response = await ctx.modelRegistry.streamSimple(ctx.model,
			{ systemPrompt, messages: [request] },
			{ signal, reasoning: ctx.thinkingLevel === "off" ? undefined : ctx.thinkingLevel }).result();
		if (response.stopReason !== "stop") throw new Error(`Controller review ended with ${response.stopReason}.`);
		return response.content.filter((part): part is { type: "text"; text: string } => part.type === "text").map((part) => part.text).join("\n");
	}

	async function establishContract(ctx: ExtensionContext, request: string, selected: string,
		filePaths: string[] | undefined, candidates: Requirement[] | undefined, signal?: AbortSignal): Promise<TaskState> {
		const sources = await requirementSources(request, ctx.cwd, selected, filePaths);
		const input = JSON.stringify({ sources, candidate_requirements: candidates ?? [] });
		const extracted = parseContractItems(await modelText(ctx, CONTRACT_EXTRACTION_PROMPT, input, signal), sources);
		return newTask(request, extracted, sources);
	}

	async function runPlanner(ctx: ExtensionContext, signal?: AbortSignal): Promise<string> {
		if (!state || !projectRoot || state.phase !== "plan" || state.lastVerification?.status !== "fail") {
			throw new Error("Planner requires an actual failed Godot verification recorded by the Controller.");
		}
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
				const plan = parsePlannerOutput(raw);
				state = acceptPlan(state, plan);
				persist();
				return state.phase === "stopped" ? nextInstruction(state) : generatorHandoff(state);
			} catch (error) {
				if (attempt === 1) throw error;
				correction = `\n\nYour previous JSON was rejected: ${error instanceof Error ? error.message : String(error)} Return one corrected JSON object.`;
			}
		}
		throw new Error("Planner did not produce a valid plan.");
	}

	async function verify(root: string, ctx: ExtensionContext, signal?: AbortSignal): Promise<{ result: Verification; handoff: string }> {
		if (state?.phase === "done" || state?.phase === "stopped") throw new Error("This task has ended. Start a new task before verifying again.");
		const submittedFingerprint = await projectFingerprint(root);
		let result = await verifyProject({ project: root, godot, signal });
		const currentFingerprint = await projectFingerprint(root);
		if (submittedFingerprint !== currentFingerprint) result = { status: "infrastructure", stage: "revision", score: 0,
			fingerprint: currentFingerprint, errors: [{ stage: "revision", message: "Project files changed during verification; submit the current workset again." }] };
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

	pi.on("tool_call", (event) => {
		if (!state?.projectPath) return;
		if (inputRevision > selectedInputRevision && event.toolName === "godot_set_project") return;
		if (inputRevision > selectedInputRevision && (state.phase === "done" || state.phase === "stopped")) return;
		if (state.phase === "done" || state.phase === "stopped") {
			return { block: true, terminate: true, reason: "This LTGD task has ended. Report the result and wait for a new user request." };
		}
		if (state.phase === "plan") {
			if (event.toolName === "godot_verify" || event.toolName === "godot_get_errors") return;
			return { block: true, terminate: true, reason: "Planning is pending. Resume with godot_verify; do not edit or inspect unrelated work." };
		}
		if (state.phase === "review") {
			if (event.toolName === "godot_finish" || REVIEW_READ_TOOLS.has(event.toolName)) return;
			return { block: true, terminate: true, reason: "Godot passed. Review only the original requirements and call godot_finish. Editing, shell commands, and optional polish are blocked." };
		}
	});

	pi.on("before_agent_start", (event) => {
		if (event.prompt.trim() && (!state?.projectPath || state.phase === "done" || state.phase === "stopped")) latestUserRequest = event.prompt.trim();
		if (!state?.projectPath || state.phase === "done" || state.phase === "stopped") {
			return { systemPrompt: event.systemPrompt + "\n\nIf the user requests Godot game development with LTGD, call godot_set_project to activate the workflow. Include task specification files in specification_files; the Controller extracts the requirement list before generation. For other tasks, leave LTGD tools unused." };
		}
		return { systemPrompt: event.systemPrompt + `\n\nFor the selected LTGD Godot game, follow this workflow:
- You are the Generator. Keep Pi's current directory. The selected project is ${state.projectPath}.
- Use godot_inspect_project and godot_inspect_scene for concise context. Read raw files only for edits. Keep all project files inside the selected directory.
- After completing the current workset, call godot_verify with a completed/unresolved evidence report for every active ID. Only an actual Godot verification failure lets the Controller call the isolated Planner. You cannot request planning yourself. Implement the whole resulting plan before verifying again.
- Work only on the original requirements, confirmed missing requirements, or the current Godot repair plan. Do not add optional goals.
- When no authorized workset item remains unmet, submit the whole workset to godot_verify immediately. Do not start an open-ended polish or inspection pass.
- If a session resumes with a pending plan, call godot_verify to resume planning without another Godot run.
- A Godot pass proves import and headless boot only. Review only the original requirements and call godot_finish before claiming completion. After a pass, no project edit or shell command is allowed until the Controller confirms a missing original requirement.
- Do not modify shared assets/ or Godot_Engine/.` };
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
		description: "Select the game output directory and extract requirements from the user task and specification files. Omit project to use game/ under Pi's current directory. List task specification files; instruction.md and task.toml in the current or selected directory are read automatically. Candidate requirements are hints only. Set new_task only after a new user request.",
		parameters: Type.Object({
			project: Type.Optional(Type.String({ description: "User-specified project or output directory; relative paths start from Pi's current directory" })),
			new_task: Type.Optional(Type.Boolean({ description: "Start a new Godot game task even if another project is active" })),
			specification_files: Type.Optional(Type.Array(Type.String(), { description: "Paths to every referenced task specification file, relative to Pi's current directory unless absolute" })),
			requirements: Type.Optional(Type.Array(Type.Object({ id: Type.String(), text: Type.String(), doneWhen: Type.Optional(Type.String()) }), { description: "Optional hints; Controller extracts the final list from task sources" })),
		}),
		executionMode: "sequential",
		async execute(_id, params, signal, _update, ctx) {
			if (state?.projectPath) {
				if (!params.new_task && state.phase === "generate" && state.attempts === 0 && !state.plan.length && !state.pendingRequirementIds?.length) {
					return { content: [{ type: "text", text: `Godot project already selected: ${state.projectPath}. Requirements remain fixed for this task.` }], details: { project: state.projectPath } };
				}
				if (!params.new_task) throw new Error("Use new_task after a new user request to start another Godot game task; current requirements cannot be replaced.");
				if (inputRevision <= selectedInputRevision) throw new Error("A new user request is required before starting another Godot game task.");
			}
			const selected = path.resolve(ctx.cwd, params.project?.trim() || "game");
			const task = await establishContract(ctx, latestUserRequest, selected, params.specification_files, params.requirements, signal);
			await fs.mkdir(selected, { recursive: true });
			projectRoot = selected;
			state = { ...task, projectPath: selected };
			selectedInputRevision = inputRevision;
			persist();
			return { content: [{ type: "text", text: `Selected Godot project: ${selected}. Game requirements:\n${state.requirements.map((item) => `- ${item.id}: ${item.text} | done when: ${item.doneWhen}`).join("\n")}\nSource quotes are retained in the Controller state. Create and edit project files there; all godot_* tools use this directory.` }], details: { project: selected } };
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
		description: "Report the whole current workset as completed or unresolved. Godot import and boot run only when all items are complete. A real failure triggers the short-context Planner.",
		parameters: Type.Object({
			workset_checks: Type.Optional(Type.Array(Type.Object({
				id: Type.String(),
				status: Type.Union([Type.Literal("completed"), Type.Literal("unresolved")]),
				evidence: Type.String(),
			}), { description: "Required for an actual Godot verification: report every current workset ID exactly once" })),
		}), executionMode: "sequential",
		async execute(_id, params, signal, _update, ctx) {
			if (!(await hasProjectFile(projectRoot))) throw new Error(`No project.godot in ${projectRoot || "a selected directory"}. Select or create the project first.`);
			if (!state) throw new Error("Select an active Godot task first.");
			if (state?.phase === "done" || state?.phase === "stopped") throw new Error("This task has ended. Start a new task before verifying again.");
			if (state.phase === "plan" && state.lastVerification?.status === "fail") {
				const previous = state.lastVerification;
				let handoff: string;
				try { handoff = await runPlanner(ctx, signal); }
				catch (error) {
					state = { ...state, phase: "stopped", plannerError: error instanceof Error ? error.message : String(error) };
					persist();
					handoff = nextInstruction(state);
				}
				return { content: [{ type: "text", text: `${compact(previous)}\n${handoff}` }], details: previous };
			}
			if (state.phase !== "generate") throw new Error("Verify only after completing the current generation workset; use godot_finish after a pass.");
			const { workset, unresolved } = validateWorksetChecks(state, params.workset_checks);
			if (unresolved.length) return { content: [{ type: "text", text: incompleteWorksetMessage(workset, unresolved) }], details: { source: workset.source, unresolved } };
			if (state.pendingRequirementIds?.length && state.lastVerification?.status === "pass" && await projectFingerprint(projectRoot) === state.lastVerification.fingerprint) {
				return { content: [{ type: "text", text: `No project files changed since review found missing requirements. ${nextInstruction(state)}` }], details: state.lastVerification };
			}
			const { result, handoff } = await verify(projectRoot, ctx, signal);
			return { content: [{ type: "text", text: `${compact(result)}\n${handoff}` }], details: result };
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

	pi.registerTool({
		name: "godot_finish", label: "Complete verified game task",
		description: "Review each original requirement after Godot passes. Missing requirements return directly to generation; otherwise finish with concrete evidence and disclose human playtest needs.",
		executionMode: "sequential",
		parameters: Type.Object({ checks: Type.Array(Type.Object({
			id: Type.String({ description: "Original requirement ID" }),
			status: Type.Union([Type.Literal("implemented"), Type.Literal("needs_playtest"), Type.Literal("missing")]),
			evidence: Type.String({ description: "Specific implementation evidence, missing behavior, or remaining playtest need" }),
			expected: Type.Optional(Type.String({ description: "What the original requirement demands" })),
			observed: Type.Optional(Type.String({ description: "What the current game does" })),
		})) }),
		async execute(_id, params) {
			if (!state || !projectRoot) throw new Error("Select an active project first.");
			const current = await inspectProject(projectRoot);
			if (state.lastVerification?.fingerprint !== current.fingerprint) throw new Error("Verify the current project files before finishing.");
			state = finishTask(state, params.checks, current.fingerprint);
			persist();
			if (state.phase === "generate") return { content: [{ type: "text", text: `Review found missing original requirements. ${nextInstruction(state)}` }], details: { missing: state.pendingRequirementIds ?? [], needsPlaytest: [] as string[] } };
			const playtests = (state.completionEvidence as typeof params.checks).filter((check) => check.status === "needs_playtest").map((check) => check.id);
			return { content: [{ type: "text", text: `Task recorded as done. Report implemented behavior and Godot verification evidence.${playtests.length ? ` Explicitly disclose that ${playtests.join(", ")} still need human playtesting.` : ""}` }], details: { missing: [] as string[], needsPlaytest: playtests } };
		},
	});

	pi.registerCommand("godot-status", {
		description: "Show the Godot-PaT task phase and latest verification",
		handler: async (_args, ctx) => ctx.ui.notify(state ? `${state.phase}; project ${projectRoot || "not selected"}; ${state.attempts} verification attempts.\n${state.lastVerification ? compact(state.lastVerification) : "No verification yet."}` : "No active task.", "info"),
	});

}
