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
	score: number;
	fingerprint: string;
	evidence: string;
}

export interface Subtask {
	id: string;
	problem: string;
	goal: string;
	suggested_files?: string[];
}

export interface DecompositionPlan {
	objective: string;
	subtasks: Subtask[];
}

export interface TaskState {
	schemaVersion: 3;
	goal: string;
	projectPath?: string;
	phase: Phase;
	attempts: number;
	lastFailure?: string;
	lastFingerprint?: string;
	lastVerification?: Verification;
	plan: Subtask[];
	planObjective?: string;
	/** Retained only when restoring a version 2 session. */
	integrationChecks?: string[];
	/** Generator-reported completed work; older records may contain verified subtask evidence. */
	solved: { id: string; evidence: string; fingerprint: string }[];
	completionEvidence?: string[];
	plannerError?: string;
}

export function newTask(goal: string): TaskState {
	return { schemaVersion: 3, goal, phase: "generate", attempts: 0, plan: [], solved: [] };
}

export function recordVerification(state: TaskState, result: Verification): TaskState {
	if (result.status === "infrastructure") return { ...state, lastVerification: result };
	const attempts = state.attempts + 1;
	if (result.status === "pass") {
		return { ...state, phase: "review", attempts, lastVerification: result, lastFingerprint: result.fingerprint };
	}
	const signature = createHash("sha256").update(JSON.stringify(result.errors.map((error) => [error.stage, error.file, error.line, error.message]))).digest("hex");
	const phase: Phase = state.lastFailure === signature && state.lastFingerprint === result.fingerprint ? "stopped" : "plan";
	return {
		...state,
		phase,
		attempts,
		lastFailure: signature,
		lastFingerprint: result.fingerprint,
		lastVerification: result,
	};
}

function nonempty(text: unknown, label: string): asserts text is string {
	if (typeof text !== "string" || !text.trim()) throw new Error(`${label} must be a nonempty string.`);
}

export function acceptPlan(state: TaskState, plan: DecompositionPlan): TaskState {
	if (state.phase !== "plan") throw new Error("Planner is available only in the plan phase.");
	if (!plan || typeof plan !== "object" || Array.isArray(plan)) throw new Error("Supply a structured plan.");
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
	return { ...state, phase: "generate", plan: subtasks, planObjective: plan.objective, integrationChecks: undefined, solved: [], completionEvidence: undefined, plannerError: undefined };
}

export function generatorHandoff(state: TaskState): string {
	if (state.phase !== "generate" || !state.plan.length) return "";
	return `Generator plan: ${JSON.stringify({
		objective: state.planObjective ?? state.goal,
		subtasks: state.plan,
	})}\nImplement the whole plan, then call godot_verify once. Suggested files are hints, not a restriction on edits. Completed subtask IDs and brief evidence may be included in that verification call.`;
}

export function recordCompletedSubtasks(state: TaskState, completed: { id: string; evidence: string }[], fingerprint: string): TaskState {
	if (state.phase !== "generate") throw new Error("Report completed work during generation.");
	if (!Array.isArray(completed) || completed.length > state.plan.length) throw new Error("Report only planned subtasks.");
	const ids = new Set<string>();
	const solved = [...state.solved];
	for (const item of completed) {
		nonempty(item.id, "Completed subtask ID");
		nonempty(item.evidence, `Evidence for ${item.id}`);
		if (ids.has(item.id) || !state.plan.some((task) => task.id === item.id)) throw new Error("Completed subtask IDs must be unique and belong to the current plan.");
		ids.add(item.id);
		const record = { id: item.id, evidence: item.evidence, fingerprint };
		const old = solved.findIndex((entry) => entry.id === item.id);
		if (old < 0) solved.push(record);
		else solved[old] = record;
	}
	return { ...state, solved };
}

export function finishTask(state: TaskState, evidence: string[], fingerprint: string): TaskState {
	if (state.phase !== "review") throw new Error("Finish only after a successful full-project review.");
	if (state.lastVerification?.status !== "pass" || state.lastVerification.fingerprint !== fingerprint) {
		throw new Error("Verify the current project files before finishing.");
	}
	if (!Array.isArray(evidence) || !evidence.length) throw new Error("Completion evidence must contain at least one requirement check.");
	evidence.forEach((item, index) => nonempty(item, `Completion evidence[${index}]`));
	return { ...state, phase: "done", completionEvidence: evidence };
}
import { createHash } from "node:crypto";
