import { Type, type UserMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import path from "node:path";
import { acceptPlan, activeWorkset, authorizeProposal, finishTask, generatorHandoff, migrateTaskState, newTask, recordCompletedWorkset, recordVerification, validatePlanScope, validateWorksetChecks, type ActiveWorkset, type DecompositionPlan, type Requirement, type ScopeDecision, type TaskState, type Verification, type WorkProposal, type WorksetCheck } from "./controller.ts";
import { verifyProject } from "./godot.ts";
import { parsePlannerOutput, plannerInput, PLANNER_SYSTEM_PROMPT } from "./planner.ts";
import { inspectProject, inspectScene } from "./project.ts";
import { parsePlanScopeDecisions, parseScopeDecision, PLAN_SCOPE_SYSTEM_PROMPT, scopeInput, SCOPE_SYSTEM_PROMPT } from "./scope.ts";

const workspace = path.resolve(import.meta.dirname, "../..");
const godot = path.join(workspace, "Godot_Engine", "Godot_v4.6.2-stable_win64_console.exe");
const REVIEW_READ_TOOLS = new Set(["read", "grep", "find", "ls", "godot_inspect_project", "godot_inspect_scene", "godot_get_errors"]);

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
		return `Authorized ${workset.source} workset: ${workset.items.map((item) => `${item.id}: ${item.goal.length > 160 ? `${item.goal.slice(0, 157)}...` : item.goal}`).join("; ")}. Work only toward an unmet item. Observations and possible improvements are not new tasks; propose genuinely necessary additional work with godot_propose_work. When this whole workset is complete, immediately call godot_verify with one evidence-backed workset_checks entry per ID. Do not continue exploring for improvements.`;
	}
	if (state.phase === "review") return `Godot import and boot passed. Classify only the original requirements (${state.requirements.map((item) => `${item.id}: ${item.text}`).join("; ")}). Call godot_finish once with evidence for each ID. A missing item needs expected and observed behavior plus concrete evidence; the Controller decides whether it authorizes more work. Use needs_playtest for behavior that exists but needs a human test. Do not seek optional improvements or edit the project.`;
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
		if (!ctx.model) throw new Error("No model is selected for scope review.");
		const request: UserMessage = { role: "user", content: [{ type: "text", text: input }], timestamp: Date.now() };
		const response = await ctx.modelRegistry.streamSimple(ctx.model,
			{ systemPrompt, messages: [request] },
			{ signal, reasoning: ctx.thinkingLevel === "off" ? undefined : ctx.thinkingLevel }).result();
		if (response.stopReason !== "stop") throw new Error(`Scope review ended with ${response.stopReason}.`);
		return response.content.filter((part): part is { type: "text"; text: string } => part.type === "text").map((part) => part.text).join("\n");
	}

	async function judgeScope(ctx: ExtensionContext, proposal: WorkProposal, signal?: AbortSignal): Promise<{ decision: ScopeDecision; reason: string }> {
		if (!state) throw new Error("No active task.");
		const requirement = state.requirements.find((item) => item.id === proposal.sourceId);
		try { return parseScopeDecision(await modelText(ctx, SCOPE_SYSTEM_PROMPT, scopeInput(state.goal, requirement, proposal), signal)); }
		catch (error) { return { decision: "uncertain", reason: `Scope could not be confirmed: ${error instanceof Error ? error.message : String(error)}` }; }
	}

	async function reviewPlanScope(ctx: ExtensionContext, parentState: TaskState, plan: DecompositionPlan, signal?: AbortSignal): Promise<void> {
		validatePlanScope(parentState, plan);
		if (plan.decision !== "revise") return;
		const parents = (parentState.lastFailureWorkIds ?? []).map((id) => parentState.workItems.find((item) => item.id === id));
		const raw = await modelText(ctx, PLAN_SCOPE_SYSTEM_PROMPT, JSON.stringify({ original_request: parentState.goal,
			authorized_work: parents, subtasks: plan.subtasks }), signal);
		const decisions = parsePlanScopeDecisions(raw, plan.subtasks!.map((item) => item.id));
		const unauthorized = plan.subtasks!.filter((item) => decisions[item.id] !== "required").map((item) => item.id);
		if (unauthorized.length) throw new Error(`Planner added unsupported work: ${unauthorized.join(", ")}. Remove it and keep only required subtasks.`);
	}

	async function runPlanner(ctx: ExtensionContext, signal?: AbortSignal, authorizedWorkId?: string): Promise<string> {
		if (!state || !projectRoot || (state.phase !== "plan" && !authorizedWorkId)) throw new Error("An authorized work item is required before planning.");
		if (!ctx.model) throw new Error("No model is selected for the Planner.");
		const authorizedWork = authorizedWorkId ? state.workItems.find((item) => item.id === authorizedWorkId && item.status === "active") : undefined;
		if (authorizedWorkId && !authorizedWork) throw new Error("Unknown or completed work item cannot be decomposed.");
		const parentState = authorizedWork ? { ...state, phase: "plan" as const, lastFailureWorkIds: [authorizedWork.id],
			carryWorkIds: activeWorkset(state).items.map((item) => item.id).filter((id) => id !== authorizedWork.id) } : state;
		const overview = await inspectProject(projectRoot);
		const input = await plannerInput(parentState, overview, authorizedWork);
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
				await reviewPlanScope(ctx, parentState, plan, signal);
				state = acceptPlan(parentState, plan);
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
		if (!state?.projectPath || inputRevision > selectedInputRevision) return;
		if (state.phase === "done" || state.phase === "stopped") {
			return { block: true, terminate: true, reason: "This LTGD task has ended. Report the result and wait for a new user request." };
		}
		if (state.phase === "plan") {
			if (event.toolName === "godot_verify" || event.toolName === "godot_get_errors") return;
			return { block: true, terminate: true, reason: "Planning is pending. Resume with godot_verify; do not edit or inspect unrelated work." };
		}
		if (state.phase === "review") {
			if (event.toolName === "godot_finish" || event.toolName === "godot_verify" || REVIEW_READ_TOOLS.has(event.toolName)) return;
			return { block: true, terminate: true, reason: "Godot passed. Review only the original requirements and call godot_finish. Editing, shell commands, and optional polish are blocked." };
		}
	});

	pi.on("before_agent_start", (event) => {
		if (event.prompt.trim() && (!state?.projectPath || state.phase === "done" || state.phase === "stopped")) latestUserRequest = event.prompt.trim();
		if (!state?.projectPath || state.phase === "done" || state.phase === "stopped") {
			return { systemPrompt: event.systemPrompt + "\n\nIf the user requests Godot game development with LTGD, call godot_set_project to activate the workflow. For other tasks, leave LTGD tools unused." };
		}
		return { systemPrompt: event.systemPrompt + `\n\nWhen working on the selected LTGD Godot game, follow this workflow; for unrelated requests, use Pi normally:
- You are the Generator. Keep Pi's current directory. The selected project is ${state.projectPath}.
- Use godot_inspect_project and godot_inspect_scene for concise context. Read raw files only for edits. Keep all project files inside the selected directory.
- After completing the current workset, call godot_verify with a completed/unresolved evidence report for every active ID. On failure the extension automatically calls an isolated, short-context Planner. Implement its whole plan before verifying again; do not call a separate planning tool.
- Only Controller-authorized work is a task. A possible improvement is a suggestion, not permission to inspect or edit further. If genuinely necessary new work is discovered, call godot_propose_work with the original requirement or observed Godot error and concrete evidence; optional or uncertain proposals do not authorize work.
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
		description: "Activate a Godot game task and select its output directory. Omit project to use game/ under Pi's current directory. Supply concise requirements from the user's request; if omitted, the full goal becomes one requirement. Set new_task only after a new user request to start another game; an active task's requirements cannot be replaced.",
		parameters: Type.Object({
			project: Type.Optional(Type.String({ description: "User-specified project or output directory; relative paths start from Pi's current directory" })),
			new_task: Type.Optional(Type.Boolean({ description: "Start a new Godot game task even if another project is active" })),
			requirements: Type.Optional(Type.Array(Type.Object({ id: Type.String(), text: Type.String(), doneWhen: Type.Optional(Type.String()) }), { description: "Stable IDs, original criteria, and optional concrete completion conditions taken only from the user's request" })),
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
		name: "godot_propose_work", label: "Propose necessary game work",
		description: "Ask the Controller whether a newly observed issue is necessary work. Optional or uncertain improvements are recorded only as suggestions. Never use this to replace the active workset.",
		parameters: Type.Object({
			basis: Type.Union([Type.Literal("user_requirement"), Type.Literal("godot_failure")]),
			sourceId: Type.String(), expected: Type.String(), observed: Type.String(), evidence: Type.String(), proposedGoal: Type.String(),
		}), executionMode: "sequential",
		async execute(_id, params, signal, _update, ctx) {
			if (!state || state.phase !== "generate") throw new Error("Additional work may be proposed only during generation.");
			const proposal = params as WorkProposal;
			if (!state.workItems.some((item) => item.id === proposal.sourceId && item.source === proposal.basis)) throw new Error("Proposal must reference an authorized original requirement or Godot failure.");
			const verdict = await judgeScope(ctx, proposal, signal);
			state = authorizeProposal(state, proposal, verdict.decision, verdict.reason);
			persist();
			return { content: [{ type: "text", text: verdict.decision === "required"
				? `Controller authorized the evidence-backed work. ${nextInstruction(state)}`
				: `Controller classified this as ${verdict.decision}; it is a suggestion only and does not authorize more work. ${verdict.reason} Continue the existing workset or verify it.` }],
				details: verdict };
		},
	});

	pi.registerTool({
		name: "godot_decompose_work", label: "Decompose authorized work",
		description: "Ask the isolated Planner to decompose one active Controller-authorized work item. Planner children must retain its source and cannot add optional goals.",
		parameters: Type.Object({ work_item_id: Type.String() }), executionMode: "sequential",
		async execute(_id, params, signal, _update, ctx) {
			if (!state || state.phase !== "generate") throw new Error("Only active generation work may be decomposed.");
			const item = state.workItems.find((entry) => entry.id === params.work_item_id && entry.status === "active");
			if (!item) throw new Error("The requested work item is not active.");
			const handoff = await runPlanner(ctx, signal, item.id);
			return { content: [{ type: "text", text: handoff || nextInstruction(state!) }], details: { workItemId: item.id } };
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
		description: "Report every active workset item as completed or unresolved. Godot import and boot run only when all items are completed. On failure, request a short-context plan. A passed, unchanged project reuses its result. After a pass, changes must be tied to an original requirement ID.",
		parameters: Type.Object({
			workset_checks: Type.Optional(Type.Array(Type.Object({
				id: Type.String(),
				status: Type.Union([Type.Literal("completed"), Type.Literal("unresolved")]),
				evidence: Type.String(),
			}), { description: "Required for an actual Godot verification: report every current workset ID exactly once" })),
			reopen_requirement_id: Type.Optional(Type.String({ description: "Original requirement ID that justified editing after the previous Godot pass" })),
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
			if (state?.phase === "review" && state.lastVerification?.status === "pass") {
				const fingerprint = await projectFingerprint(projectRoot);
				if (fingerprint === state.lastVerification.fingerprint) {
					return { content: [{ type: "text", text: `${compact(state.lastVerification)}\nProject unchanged; reused the last successful verification. ${nextInstruction(state)}` }], details: state.lastVerification };
				}
				const id = params.reopen_requirement_id?.trim();
				if (!id || !state.requirements.some((item) => item.id === id)) throw new Error("Project changed after Godot passed. Name the unmet original requirement in reopen_requirement_id before re-verifying.");
				const { workset, unresolved } = validateWorksetChecks(state, params.workset_checks, id);
				if (unresolved.length) return { content: [{ type: "text", text: incompleteWorksetMessage(workset, unresolved) }], details: { source: workset.source, unresolved } };
				state = { ...state, phase: "generate", pendingRequirements: [id], plan: [], planObjective: undefined, solved: [] };
				persist();
			}
			const { workset, unresolved } = validateWorksetChecks(state, params.workset_checks);
			if (unresolved.length) return { content: [{ type: "text", text: incompleteWorksetMessage(workset, unresolved) }], details: { source: workset.source, unresolved } };
			if (state.pendingRequirements?.length && state.lastVerification?.status === "pass" && await projectFingerprint(projectRoot) === state.lastVerification.fingerprint) {
				return { content: [{ type: "text", text: `No project files changed since review found missing requirements. ${nextInstruction(state)}` }], details: state.lastVerification };
			}
			state = recordCompletedWorkset(state, params.workset_checks!, await projectFingerprint(projectRoot));
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
		description: "Review only the fixed original requirements after Godot passes. A missing item needs concrete expected/observed evidence and a Controller scope decision; optional or uncertain suggestions cannot reopen work.",
		executionMode: "sequential",
		parameters: Type.Object({ checks: Type.Array(Type.Object({
			id: Type.String({ description: "Original requirement ID" }),
			status: Type.Union([Type.Literal("implemented"), Type.Literal("needs_playtest"), Type.Literal("missing")]),
			evidence: Type.String({ description: "Specific implementation evidence, missing behavior, or remaining playtest need" }),
			expected: Type.Optional(Type.String({ description: "Required when status is missing: what the original requirement demands" })),
			observed: Type.Optional(Type.String({ description: "Required when status is missing: what the current game actually does" })),
		})) }),
		async execute(_id, params, signal, _update, ctx) {
			if (!state || !projectRoot) throw new Error("Select an active project first.");
			const current = await inspectProject(projectRoot);
			if (state.lastVerification?.fingerprint !== current.fingerprint) throw new Error("Verify the current project files before finishing.");
			const decisions: Record<string, ScopeDecision> = {};
			const suggestions = [...(state.suggestions ?? [])];
			for (const check of params.checks.filter((item) => item.status === "missing")) {
				if (!check.expected?.trim() || !check.observed?.trim() || !check.evidence.trim()) throw new Error(`Missing requirement ${check.id} needs expected, observed, and evidence.`);
				const requirement = state.requirements.find((item) => item.id === check.id);
				if (!requirement) throw new Error(`Unknown original requirement: ${check.id}.`);
				const proposal: WorkProposal = { basis: "user_requirement", sourceId: check.id, expected: check.expected,
					observed: check.observed, evidence: check.evidence, proposedGoal: requirement.text };
				const verdict = await judgeScope(ctx, proposal, signal);
				decisions[check.id] = verdict.decision;
				if (verdict.decision !== "required") suggestions.push({ proposal, decision: verdict.decision, reason: verdict.reason });
			}
			state = finishTask({ ...state, suggestions }, params.checks, current.fingerprint, decisions);
			persist();
			if (state.phase === "stopped") return { content: [{ type: "text", text: `Automatic work stopped. ${state.plannerError} Report the unresolved requirement to the user without claiming completion.` }],
				details: { needsReview: params.checks.filter((check) => check.status === "missing").map((check) => check.id) } };
			if (state.phase === "generate") return { content: [{ type: "text", text: `Review found missing original requirements. ${nextInstruction(state)}` }], details: { missing: state.pendingRequirements ?? [], needsPlaytest: [] as string[] } };
			const playtests = (state.completionEvidence as typeof params.checks).filter((check) => check.status === "needs_playtest").map((check) => check.id);
			return { content: [{ type: "text", text: `Task recorded as done. Report implemented behavior and Godot verification evidence.${playtests.length ? ` Explicitly disclose that ${playtests.join(", ")} still need human playtesting.` : ""}` }], details: { missing: [] as string[], needsPlaytest: playtests } };
		},
	});

	pi.registerCommand("godot-status", {
		description: "Show the Godot-PaT task phase and latest verification",
		handler: async (_args, ctx) => ctx.ui.notify(state ? `${state.phase}; project ${projectRoot || "not selected"}; ${state.attempts} verification attempts.\n${state.lastVerification ? compact(state.lastVerification) : "No verification yet."}` : "No active task.", "info"),
	});

}
