export type Phase = "direct" | "repair" | "plan" | "execute_plan" | "done" | "stopped";
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
	goal: string;
	targets: string[];
	depends_on: string[];
}

export interface TaskState {
	goal: string;
	projectPath?: string;
	phase: Phase;
	attempts: number;
	bestScore: number;
	noProgress: number;
	lastFailure?: string;
	lastFingerprint?: string;
	lastVerification?: Verification;
	plan: Subtask[];
	currentSubtask: number;
	solved: { id: string; evidence: string; fingerprint: string }[];
}

export function newTask(goal: string): TaskState {
	return { goal, phase: "direct", attempts: 0, bestScore: -1, noProgress: 0, plan: [], currentSubtask: 0, solved: [] };
}

export function recordVerification(state: TaskState, result: Verification): TaskState {
	if (result.status === "infrastructure") return { ...state, lastVerification: result };
	const attempts = state.attempts + 1;
	if (result.status === "pass") {
		return { ...state, phase: state.plan.length && state.currentSubtask < state.plan.length ? "execute_plan" : "done", attempts, lastVerification: result, lastFingerprint: result.fingerprint };
	}
	const signature = JSON.stringify(result.errors.map((error) => [error.stage, error.file, error.line, error.message]));
	const improved = result.score > state.bestScore;
	const noProgress = improved ? 0 : state.noProgress + 1;
	let phase: Phase = state.phase === "direct" || state.phase === "done" ? "repair" : "plan";
	if (state.phase === "plan") phase = "plan";
	if (state.phase === "execute_plan") phase = "repair";
	if ((state.lastFailure === signature && state.lastFingerprint === result.fingerprint) || noProgress >= 3 || attempts >= 6) {
		phase = "stopped";
	}
	return {
		...state,
		phase,
		attempts,
		bestScore: Math.max(state.bestScore, result.score),
		noProgress,
		lastFailure: signature,
		lastFingerprint: result.fingerprint,
		lastVerification: result,
	};
}

export function acceptPlan(state: TaskState, subtasks: Subtask[]): TaskState {
	if (state.phase !== "plan") throw new Error("Planner is available only after a failed repair.");
	if (subtasks.length < 1 || subtasks.length > 6) throw new Error("Plan must contain 1 to 6 subtasks.");
	const seen = new Set<string>();
	for (const task of subtasks) {
		if (!task.id.trim() || !task.goal.trim() || seen.has(task.id)) throw new Error("Subtask IDs and goals must be unique and nonempty.");
		if (task.depends_on.some((dependency) => !seen.has(dependency))) throw new Error("Dependencies must refer to earlier subtasks.");
		seen.add(task.id);
	}
	return { ...state, phase: "execute_plan", plan: subtasks, currentSubtask: 0 };
}

export function completeSubtask(state: TaskState, evidence: string, fingerprint: string): TaskState {
	if (state.phase !== "execute_plan" || !state.plan[state.currentSubtask]) throw new Error("No active planned subtask.");
	if (state.lastVerification?.status !== "pass" || state.lastVerification.fingerprint !== fingerprint) {
		throw new Error("Verify the current files successfully before completing this subtask.");
	}
	if (!evidence.trim()) throw new Error("Describe what requirement behavior was checked.");
	const task = state.plan[state.currentSubtask];
	const currentSubtask = state.currentSubtask + 1;
	return {
		...state,
		phase: currentSubtask === state.plan.length ? "done" : "execute_plan",
		currentSubtask,
		solved: [...state.solved, { id: task.id, evidence: evidence.slice(0, 500), fingerprint }],
	};
}
