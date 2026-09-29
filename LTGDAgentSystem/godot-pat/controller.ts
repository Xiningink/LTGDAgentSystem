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
}

export interface RequirementCheck {
	id: string;
	status: "implemented" | "missing";
	evidence: string;
}

export type WorksetSource = "user" | "planner" | "review";

export interface ActiveWorkset {
	source: WorksetSource;
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
	pendingRequirements?: string[];
	projectPath?: string;
	phase: Phase;
	attempts: number;
	lastFailure?: string;
	unchangedFailureStreak?: number;
	lastFingerprint?: string;
	lastVerification?: Verification;
	lastReviewFailureFingerprint?: string;
	plan: Subtask[];
	planObjective?: string;
	completionEvidence?: RequirementCheck[] | string[];
	plannerError?: string;
}

export function newTask(goal: string, requirements?: Requirement[]): TaskState {
	const selected = requirements?.length ? requirements : [{ id: "R1", text: goal }];
	const seen = new Set<string>();
	for (const item of selected) {
		if (!item || typeof item !== "object") throw new Error("Each requirement must be an object.");
		nonempty(item.id, "Requirement ID");
		nonempty(item.text, `Requirement ${item.id}`);
		if (seen.has(item.id)) throw new Error("Requirement IDs must be unique.");
		seen.add(item.id);
	}
	return { schemaVersion: 7, goal, requirements: selected, phase: "generate", attempts: 0, plan: [] };
}

export function recordVerification(state: TaskState, result: Verification): TaskState {
	if (result.status === "infrastructure") return { ...state, lastVerification: result };
	const attempts = state.attempts + 1;
	if (result.status === "pass") {
		return { ...state, phase: "review", attempts, lastVerification: result, lastFingerprint: result.fingerprint, lastFailure: undefined, unchangedFailureStreak: 0 };
	}
	const signature = createHash("sha256").update(JSON.stringify(result.errors.map((error) => [error.stage, error.file, error.line, error.message]))).digest("hex");
	const sameFailure = state.lastFailure === signature;
	const unchangedFailureStreak = sameFailure ? (state.unchangedFailureStreak ?? 0) + 1 : 0;
	const phase: Phase = sameFailure && (state.lastFingerprint === result.fingerprint || unchangedFailureStreak >= 2) ? "stopped" : "plan";
	return {
		...state,
		phase,
		attempts,
		lastFailure: signature,
		unchangedFailureStreak,
		lastFingerprint: result.fingerprint,
		lastVerification: result,
		plannerError: phase === "stopped" ? "The same Godot errors persisted after repeated revisions." : undefined,
	};
}

function nonempty(text: unknown, label: string): asserts text is string {
	if (typeof text !== "string" || !text.trim()) throw new Error(`${label} must be a nonempty string.`);
}

export function activeWorkset(state: TaskState): ActiveWorkset {
	if (state.phase !== "generate") throw new Error("An active workset is available only during generation.");
	if (state.pendingRequirements?.length) {
		return {
			source: "review",
			items: state.pendingRequirements.map((id) => {
				const requirement = state.requirements.find((item) => item.id === id);
				if (!requirement) throw new Error(`Unknown pending requirement: ${id}.`);
				return { id, goal: requirement.text };
			}),
		};
	}
	if (state.plan.length) return { source: "planner", items: state.plan.map(({ id, goal }) => ({ id, goal })) };
	return { source: "user", items: state.requirements.map(({ id, text }) => ({ id, goal: text })) };
}

export function acceptPlan(state: TaskState, plan: DecompositionPlan): TaskState {
	if (state.phase !== "plan") throw new Error("Planner is available only in the plan phase.");
	if (!plan || typeof plan !== "object" || Array.isArray(plan)) throw new Error("Supply a structured plan.");
	if (plan.decision !== "revise" && plan.decision !== "cannot_resolve_in_project") throw new Error("Planner decision must be revise or cannot_resolve_in_project.");
	nonempty(plan.reason, "Plan reason");
	if (plan.decision === "cannot_resolve_in_project") {
		if (plan.subtasks !== undefined && (!Array.isArray(plan.subtasks) || plan.subtasks.length)) throw new Error("A no-change decision cannot contain subtasks.");
		if (!Array.isArray(plan.evidence) || !plan.evidence.length) throw new Error("A no-change decision requires verification evidence.");
		plan.evidence.forEach((item, index) => nonempty(item, `Planner evidence[${index}]`));
		return { ...state, phase: "stopped", plan: [], planObjective: undefined, plannerError: `${plan.reason}${plan.evidence?.length ? ` Evidence: ${plan.evidence.join("; ")}` : ""}` };
	}
	nonempty(plan.objective, "Plan objective");
	const subtasks = plan.subtasks;
	if (!Array.isArray(subtasks) || !subtasks.length) throw new Error("Plan must contain subtasks.");
	const seen = new Set<string>();
	for (const task of subtasks) {
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
	return { ...state, phase: "generate", plan: subtasks, planObjective: plan.objective, pendingRequirements: undefined, completionEvidence: undefined, plannerError: undefined };
}

export function generatorHandoff(state: TaskState): string {
	if (state.phase !== "generate" || !state.plan.length) return "";
	const workset = activeWorkset(state);
	return `Generator plan: ${JSON.stringify({
		objective: state.planObjective ?? state.goal,
		subtasks: state.plan,
	})}\nCurrent ${workset.source} workset: ${workset.items.map((item) => `${item.id}: ${item.goal}`).join("; ")}. Implement only this repair plan, then end the Generator turn. The Executor will verify automatically. Suggested files are hints, not a restriction on edits; do not add optional objectives.`;
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
		if (!["implemented", "missing"].includes(check.status)) throw new Error(`Invalid status for ${check.id}.`);
		nonempty(check.evidence, `Evidence for ${check.id}`);
		seen.add(check.id);
	}
	const missing = checks.filter((check) => check.status === "missing").map((check) => check.id);
	if (missing.length) return { ...state, phase: "plan", plan: [], planObjective: undefined, pendingRequirements: missing, completionEvidence: checks, lastReviewFailureFingerprint: fingerprint };
	return { ...state, phase: "done", pendingRequirements: [], completionEvidence: checks, lastReviewFailureFingerprint: undefined };
}
import { createHash } from "node:crypto";
