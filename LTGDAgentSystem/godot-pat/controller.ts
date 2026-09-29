export type Phase = "generate" | "plan" | "review" | "done" | "stopped";

export interface Failure {
	stage: string;
	message: string;
	file?: string;
	line?: number;
}

export interface Verification {
	status: "pass" | "fail" | "infrastructure";
	stage: string;
	errors: Failure[];
	warnings?: Failure[];
	fingerprint: string;
}

export interface RepairStep {
	problem: string;
	goal: string;
	suggested_files?: string[];
}

export interface RepairPlan {
	decision: "revise" | "cannot_resolve_in_project";
	reason: string;
	subtasks?: RepairStep[];
	evidence?: string[];
}

export interface RequirementReview {
	status: "implemented" | "missing";
	evidence: string;
}

export interface TaskState {
	goal: string;
	projectPath?: string;
	phase: Phase;
	lastVerification?: Verification;
	failureFingerprint?: string;
	reviewFailure?: string;
	plan?: RepairStep[];
	completionEvidence?: string;
	stopReason?: string;
}

function nonempty(text: unknown, label: string): asserts text is string {
	if (typeof text !== "string" || !text.trim()) throw new Error(`${label} must be a nonempty string.`);
}

export function newTask(goal: string): TaskState {
	nonempty(goal, "Game request");
	return { goal, phase: "generate" };
}

export function recordVerification(state: TaskState, result: Verification): TaskState {
	if (result.status === "infrastructure") {
		return { ...state, phase: "stopped", lastVerification: result, stopReason: result.errors.map((error) => error.message).join("; ") };
	}
	if (result.status === "pass") {
		return { ...state, phase: "review", lastVerification: result, failureFingerprint: undefined, plan: undefined, reviewFailure: undefined };
	}
	return { ...state, phase: "plan", lastVerification: result, failureFingerprint: result.fingerprint, plan: undefined, reviewFailure: undefined };
}

export function acceptPlan(state: TaskState, plan: RepairPlan): TaskState {
	if (state.phase !== "plan") throw new Error("Planner requires a confirmed Executor failure.");
	if (!plan || typeof plan !== "object" || Array.isArray(plan)) throw new Error("Planner must return one object.");
	nonempty(plan.reason, "Plan reason");
	if (plan.decision === "cannot_resolve_in_project") {
		if (!Array.isArray(plan.evidence) || !plan.evidence.length) throw new Error("A stop decision requires evidence.");
		plan.evidence.forEach((item) => nonempty(item, "Stop evidence"));
		if (plan.subtasks?.length) throw new Error("A stop decision cannot include repair steps.");
		return { ...state, phase: "stopped", plan: undefined, stopReason: `${plan.reason} Evidence: ${plan.evidence.join("; ")}` };
	}
	if (plan.decision !== "revise" || !Array.isArray(plan.subtasks) || !plan.subtasks.length) {
		throw new Error("A repair plan requires nonempty subtasks.");
	}
	for (const step of plan.subtasks) {
		if (!step || typeof step !== "object" || Array.isArray(step)) throw new Error("Each repair step must be an object.");
		nonempty(step.problem, "Repair problem");
		nonempty(step.goal, "Repair goal");
		if (step.suggested_files !== undefined && (!Array.isArray(step.suggested_files) || step.suggested_files.some((file) => typeof file !== "string"))) {
			throw new Error("Suggested files must be strings.");
		}
	}
	return { ...state, phase: "generate", plan: plan.subtasks, stopReason: undefined };
}

export function generatorHandoff(state: TaskState): string {
	if (state.phase !== "generate" || !state.plan?.length) return "";
	return `Repair only these confirmed failures: ${JSON.stringify(state.plan)}. Then end this Generator turn; the Executor verifies automatically. Suggested files are hints, not extra objectives.`;
}

export function finishTask(state: TaskState, review: RequirementReview, fingerprint: string): TaskState {
	if (state.phase !== "review" || state.lastVerification?.status !== "pass" || state.lastVerification.fingerprint !== fingerprint) {
		throw new Error("Requirement review requires a current Godot PASS.");
	}
	if (!review || !["implemented", "missing"].includes(review.status)) throw new Error("Invalid requirement review status.");
	nonempty(review.evidence, "Requirement review evidence");
	if (review.status === "missing") {
		return { ...state, phase: "plan", reviewFailure: review.evidence, failureFingerprint: fingerprint };
	}
	return { ...state, phase: "done", reviewFailure: undefined, failureFingerprint: undefined, completionEvidence: review.evidence };
}
