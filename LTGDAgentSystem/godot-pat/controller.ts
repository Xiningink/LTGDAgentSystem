import { createHash } from "node:crypto";

export type Phase = "generate" | "plan" | "review" | "done" | "stopped";
export type VerificationStatus = "pass" | "fail" | "infrastructure";

export interface Failure {
	stage: string;
	message: string;
	file?: string;
	line?: number;
}

export interface Verification {
	status: VerificationStatus;
	stage: string;
	errors: Failure[];
	warnings?: Failure[];
	score: number;
	fingerprint: string;
}

export interface Subtask {
	id: string;
	problem: string;
	goal: string;
	suggested_files?: string[];
}

export interface Requirement {
	id: string;
	text: string;
	doneWhen?: string;
	sourceEvidence?: { sourceId: string; quote: string }[];
}

export interface RequirementSource {
	id: string;
	text: string;
}

export interface RequirementCheck {
	id: string;
	status: "implemented" | "needs_playtest" | "missing";
	evidence: string;
	expected?: string;
	observed?: string;
}

export interface WorksetCheck {
	id: string;
	status: "completed" | "unresolved";
	evidence: string;
}

export interface ActiveWorkset {
	source: "user" | "planner" | "review";
	items: { id: string; goal: string }[];
}

export interface DecompositionPlan {
	decision: "revise" | "cannot_resolve_in_project";
	reason: string;
	objective?: string;
	subtasks?: Subtask[];
	evidence?: string[];
}

export interface TaskState {
	schemaVersion: 7;
	goal: string;
	requirements: Requirement[];
	projectPath?: string;
	phase: Phase;
	pendingRequirementIds?: string[];
	lastVerification?: Verification;
	lastFailureSignature?: string;
	unchangedFailureStreak?: number;
	plan: Subtask[];
	planObjective?: string;
	completionEvidence?: RequirementCheck[] | string[];
	plannerError?: string;
	attempts: number;
}

function nonempty(text: unknown, label: string): asserts text is string {
	if (typeof text !== "string" || !text.trim()) throw new Error(`${label} must be a nonempty string.`);
}

export function newTask(goal: string, requirements?: Requirement[], sources?: RequirementSource[]): TaskState {
	nonempty(goal, "Task goal");
	const selected = (requirements?.length ? requirements : [{ id: "R1", text: goal }]).map((item) => ({ ...item,
		...(item.sourceEvidence ? { sourceEvidence: item.sourceEvidence.map((evidence) => ({ ...evidence })) } : {}) }));
	const sourceById = new Map(sources?.map((source) => [source.id, source.text]));
	const seen = new Set<string>();
	for (const item of selected) {
		if (!item || typeof item !== "object") throw new Error("Each requirement must be an object.");
		nonempty(item.id, "Requirement ID");
		nonempty(item.text, `Requirement ${item.id}`);
		if (item.doneWhen !== undefined) nonempty(item.doneWhen, `Completion condition for ${item.id}`);
		if (seen.has(item.id)) throw new Error("Requirement IDs must be unique.");
		seen.add(item.id);
		if (sources) {
			nonempty(item.doneWhen, `Completion condition for ${item.id}`);
			if (!item.sourceEvidence?.length) throw new Error(`Requirement ${item.id} needs source evidence.`);
			for (const evidence of item.sourceEvidence) {
				if (!sourceById.get(evidence.sourceId)?.includes(evidence.quote)) throw new Error(`Requirement ${item.id} has invalid source evidence.`);
			}
		}
	}
	return { schemaVersion: 7, goal, requirements: selected, phase: "generate", plan: [], attempts: 0 };
}

export function migrateTaskState(loaded: Omit<Partial<TaskState>, "schemaVersion" | "phase"> & {
	goal: string; phase?: string; schemaVersion?: number; pendingRequirements?: string[]; lastFailure?: string;
}): TaskState {
	let base: TaskState;
	try { base = newTask(loaded.goal, loaded.requirements); }
	catch (error) {
		const fallback = newTask(loaded.goal);
		return { ...fallback, projectPath: loaded.projectPath, phase: "stopped",
			plannerError: `Saved requirements are invalid: ${error instanceof Error ? error.message : String(error)}` };
	}
	const legacyDone = loaded.phase === "done" && (!Array.isArray(loaded.completionEvidence) || !loaded.completionEvidence.length);
	const phase: Phase = legacyDone ? "review" : ["generate", "plan", "review", "done", "stopped"].includes(loaded.phase ?? "")
		? loaded.phase as Phase : "generate";
	return { ...base, projectPath: loaded.projectPath, phase, attempts: loaded.attempts ?? 0,
		pendingRequirementIds: loaded.pendingRequirementIds ?? loaded.pendingRequirements,
		lastVerification: loaded.lastVerification, lastFailureSignature: loaded.lastFailureSignature ?? loaded.lastFailure,
		unchangedFailureStreak: loaded.unchangedFailureStreak, plan: (loaded.plan ?? []).map((task) => ({
			id: task.id, problem: task.problem ?? "Repair the current Godot failure.", goal: task.goal,
			suggested_files: task.suggested_files ?? (task as Subtask & { targets?: string[] }).targets,
		})), planObjective: loaded.planObjective, completionEvidence: loaded.completionEvidence,
		plannerError: loaded.plannerError };
}

export function recordVerification(state: TaskState, result: Verification): TaskState {
	if (result.status === "infrastructure") return { ...state, lastVerification: result };
	const attempts = state.attempts + 1;
	if (result.status === "pass") return { ...state, phase: "review", attempts, lastVerification: result,
		lastFailureSignature: undefined, unchangedFailureStreak: 0 };
	const signature = createHash("sha256").update(JSON.stringify(result.errors.map((error) =>
		[error.stage, error.file, error.line, error.message]))).digest("hex");
	const sameFailure = state.lastFailureSignature === signature;
	const unchangedFailureStreak = sameFailure ? (state.unchangedFailureStreak ?? 0) + 1 : 0;
	const phase: Phase = sameFailure && (state.lastVerification?.fingerprint === result.fingerprint || unchangedFailureStreak >= 2)
		? "stopped" : "plan";
	return { ...state, phase, attempts, lastVerification: result, lastFailureSignature: signature,
		unchangedFailureStreak, plannerError: phase === "stopped" ? "The same Godot errors persisted after repeated revisions." : undefined };
}

export function activeWorkset(state: TaskState): ActiveWorkset {
	if (state.phase !== "generate") throw new Error("An active workset is available only during generation.");
	if (state.pendingRequirementIds?.length) return { source: "review", items: state.pendingRequirementIds.map((id) => {
		const requirement = state.requirements.find((item) => item.id === id);
		if (!requirement) throw new Error(`Unknown pending requirement: ${id}.`);
		return { id, goal: requirement.text };
	}) };
	if (state.plan.length) return { source: "planner", items: state.plan.map(({ id, goal }) => ({ id, goal })) };
	return { source: "user", items: state.requirements.map(({ id, text }) => ({ id, goal: text })) };
}

export function validateWorksetChecks(state: TaskState, checks: WorksetCheck[] | undefined): { workset: ActiveWorkset; unresolved: WorksetCheck[] } {
	const workset = activeWorkset(state);
	if (!Array.isArray(checks)) throw new Error(`Report every ${workset.source} workset item in workset_checks before verification.`);
	const expected = new Set(workset.items.map((item) => item.id));
	const seen = new Set<string>();
	for (const check of checks) {
		if (!check || typeof check !== "object") throw new Error("Each workset check must be an object.");
		if (!expected.has(check.id)) throw new Error(`Unknown active workset ID: ${check.id}.`);
		if (seen.has(check.id)) throw new Error(`Duplicate workset ID: ${check.id}.`);
		if (check.status !== "completed" && check.status !== "unresolved") throw new Error(`Invalid workset status for ${check.id}.`);
		nonempty(check.evidence, `Evidence for ${check.id}`);
		seen.add(check.id);
	}
	if (seen.size !== expected.size) throw new Error(`Report every ${workset.source} workset item exactly once. Missing: ${workset.items.filter((item) => !seen.has(item.id)).map((item) => item.id).join(", ")}.`);
	return { workset, unresolved: checks.filter((check) => check.status === "unresolved") };
}

export function acceptPlan(state: TaskState, plan: DecompositionPlan): TaskState {
	if (state.phase !== "plan" || state.lastVerification?.status !== "fail") {
		throw new Error("Planner requires an actual failed Godot verification recorded by the Controller.");
	}
	if (!plan || typeof plan !== "object" || Array.isArray(plan)) throw new Error("Supply a structured plan.");
	if (plan.decision !== "revise" && plan.decision !== "cannot_resolve_in_project") throw new Error("Planner decision must be revise or cannot_resolve_in_project.");
	nonempty(plan.reason, "Plan reason");
	if (plan.decision === "cannot_resolve_in_project") {
		if (plan.subtasks !== undefined && (!Array.isArray(plan.subtasks) || plan.subtasks.length)) throw new Error("A no-change decision cannot contain subtasks.");
		if (!Array.isArray(plan.evidence) || !plan.evidence.length) throw new Error("A no-change decision requires verification evidence.");
		plan.evidence.forEach((item, index) => nonempty(item, `Planner evidence[${index}]`));
		return { ...state, phase: "stopped", plan: [], planObjective: undefined,
			plannerError: `${plan.reason} Evidence: ${plan.evidence.join("; ")}` };
	}
	nonempty(plan.objective, "Plan objective");
	if (!Array.isArray(plan.subtasks) || !plan.subtasks.length) throw new Error("Plan must contain subtasks.");
	const seen = new Set<string>();
	for (const task of plan.subtasks) {
		if (!task || typeof task !== "object" || Array.isArray(task)) throw new Error("Each subtask must be an object.");
		nonempty(task.id, "Subtask ID");
		nonempty(task.problem, `Problem for ${task.id}`);
		nonempty(task.goal, `Goal for ${task.id}`);
		if (seen.has(task.id)) throw new Error("Subtask IDs must be unique within the plan.");
		if (task.suggested_files !== undefined && (!Array.isArray(task.suggested_files) || task.suggested_files.some((file) => typeof file !== "string"))) {
			throw new Error(`Suggested files for ${task.id} must be strings.`);
		}
		seen.add(task.id);
	}
	return { ...state, phase: "generate", plan: plan.subtasks, planObjective: plan.objective,
		pendingRequirementIds: undefined, completionEvidence: undefined, plannerError: undefined };
}

export function generatorHandoff(state: TaskState): string {
	if (state.phase !== "generate" || !state.plan.length) return "";
	const workset = activeWorkset(state);
	return `Generator plan: ${JSON.stringify({ objective: state.planObjective ?? state.goal, subtasks: state.plan })}\nCurrent ${workset.source} workset: ${workset.items.map((item) => `${item.id}: ${item.goal}`).join("; ")}. Complete the whole workset, then call godot_verify once with workset_checks for every ID. If an item is unresolved, continue only that item. Suggested files are hints, not a restriction on edits; do not add optional objectives.`;
}

export function finishTask(state: TaskState, checks: RequirementCheck[], fingerprint: string): TaskState {
	if (state.phase !== "review") throw new Error("Finish only after a successful full-project review.");
	if (state.lastVerification?.status !== "pass" || state.lastVerification.fingerprint !== fingerprint) {
		throw new Error("Verify the current project files before finishing.");
	}
	if (!Array.isArray(checks) || checks.length !== state.requirements.length) throw new Error("Review every original requirement exactly once.");
	const expected = new Set(state.requirements.map((item) => item.id));
	const seen = new Set<string>();
	for (const check of checks) {
		if (!check || typeof check !== "object") throw new Error("Each requirement check must be an object.");
		if (!expected.has(check.id) || seen.has(check.id)) throw new Error("Requirement checks must use each original ID exactly once.");
		if (!["implemented", "needs_playtest", "missing"].includes(check.status)) throw new Error(`Invalid status for ${check.id}.`);
		nonempty(check.evidence, `Evidence for ${check.id}`);
		seen.add(check.id);
	}
	const missing = checks.filter((check) => check.status === "missing").map((check) => check.id);
	if (missing.length) return { ...state, phase: "generate", pendingRequirementIds: missing,
		plan: [], planObjective: undefined, completionEvidence: checks };
	return { ...state, phase: "done", pendingRequirementIds: [], completionEvidence: checks };
}
