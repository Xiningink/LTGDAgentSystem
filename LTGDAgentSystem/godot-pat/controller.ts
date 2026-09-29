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
	parentWorkItemId?: string;
	suggested_files?: string[];
}

export interface Requirement {
	id: string;
	text: string;
	doneWhen?: string;
}

export interface RequirementCheck {
	id: string;
	status: "implemented" | "needs_playtest" | "missing";
	evidence: string;
	expected?: string;
	observed?: string;
}

export interface WorkItem {
	id: string;
	goal: string;
	source: "user_requirement" | "godot_failure" | "requirement_gap";
	sourceId: string;
	parentWorkItemId?: string;
	doneWhen: string;
	status: "active" | "reported_complete" | "closed" | "blocked";
	originEvidence: string;
	completionEvidence?: string;
}

export interface WorkProposal {
	basis: "user_requirement" | "godot_failure";
	sourceId: string;
	expected: string;
	observed: string;
	evidence: string;
	proposedGoal: string;
}

export type ScopeDecision = "required" | "optional" | "uncertain";

export type WorksetSource = "user" | "planner" | "review";

export interface ActiveWorkset {
	source: WorksetSource;
	items: { id: string; goal: string }[];
}

export interface WorksetCheck {
	id: string;
	status: "completed" | "unresolved";
	evidence: string;
}

export interface DecompositionPlan {
	decision: "revise" | "cannot_resolve_in_project";
	reason: string;
	objective?: string;
	subtasks?: Subtask[];
	evidence?: string[];
}

export interface TaskState {
	schemaVersion: 5;
	goal: string;
	requirements: Requirement[];
	workItems: WorkItem[];
	extraWorkIds?: string[];
	lastFailureWorkIds?: string[];
	suggestions?: { proposal: WorkProposal; decision: Exclude<ScopeDecision, "required">; reason: string }[];
	pendingRequirements?: string[];
	projectPath?: string;
	phase: Phase;
	attempts: number;
	lastFailure?: string;
	unchangedFailureStreak?: number;
	lastFingerprint?: string;
	lastVerification?: Verification;
	plan: Subtask[];
	planObjective?: string;
	/** Retained only when restoring a version 2 session. */
	integrationChecks?: string[];
	/** Generator-reported completed work; older records may contain verified subtask evidence. */
	solved: { id: string; evidence: string; fingerprint: string }[];
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
		if (item.doneWhen !== undefined) nonempty(item.doneWhen, `Completion condition for ${item.id}`);
		if (seen.has(item.id)) throw new Error("Requirement IDs must be unique.");
		seen.add(item.id);
	}
	return {
		schemaVersion: 5, goal, requirements: selected, phase: "generate", attempts: 0, plan: [], solved: [],
		workItems: selected.map((item) => ({ id: item.id, goal: item.text, source: "user_requirement", sourceId: item.id,
			doneWhen: item.doneWhen ?? item.text, status: "active", originEvidence: goal })),
	};
}

export function migrateTaskState(loaded: Omit<Partial<TaskState>, "schemaVersion" | "phase"> & { goal: string; phase?: string; schemaVersion?: number }): TaskState {
	const requirements = loaded.requirements?.length ? loaded.requirements : [{ id: "R1", text: loaded.goal }];
	const base = newTask(loaded.goal, requirements);
	const legacyDone = loaded.phase === "done" && (!Array.isArray(loaded.completionEvidence) || !loaded.completionEvidence.length);
	const phase = legacyDone ? "review" : ["direct", "repair", "execute_plan"].includes(loaded.phase ?? "") ? "generate" : loaded.phase ?? "generate";
	const plan = (loaded.plan ?? []).map((task) => ({ ...task, problem: task.problem ?? "Continue the previously planned subtask.",
		suggested_files: task.suggested_files ?? (task as Subtask & { targets?: string[] }).targets }));
	let workItems = loaded.workItems?.length ? loaded.workItems : base.workItems;
	let lastFailureWorkIds = loaded.lastFailureWorkIds;
	if (!loaded.workItems?.length && loaded.lastVerification?.status === "fail") {
		const failures: WorkItem[] = loaded.lastVerification.errors.map((error, index) => ({
			id: `E${loaded.attempts ?? 1}-${index + 1}`, goal: error.message, source: "godot_failure",
			sourceId: `E${loaded.attempts ?? 1}-${index + 1}`, doneWhen: `The observed ${error.stage} error no longer occurs.`,
			status: "active", originEvidence: error.message,
		}));
		workItems = [...workItems, ...failures];
		lastFailureWorkIds = failures.map((item) => item.id);
	}
	if (!loaded.workItems?.length && plan.length) {
		const parent = workItems.find((item) => item.id === lastFailureWorkIds?.[0])
			?? workItems.find((item) => item.id === loaded.pendingRequirements?.[0]);
		if (parent) workItems = [...workItems, ...plan.map((task) => ({ id: task.id, goal: task.goal,
			source: parent.source, sourceId: parent.sourceId, parentWorkItemId: parent.id, doneWhen: task.goal,
			status: "active" as const, originEvidence: parent.originEvidence }))];
		else return { ...base, ...loaded, schemaVersion: 5, phase: "stopped", requirements, plan, workItems,
			plannerError: "An older plan has no traceable work source and needs review before continuing.", solved: loaded.solved ?? [] };
	}
	return { ...base, ...loaded, schemaVersion: 5, requirements, phase: phase as Phase, plan, workItems,
		lastFailureWorkIds, solved: loaded.solved ?? [] };
}

export function recordVerification(state: TaskState, result: Verification): TaskState {
	if (result.status === "infrastructure") return { ...state, lastVerification: result };
	const attempts = state.attempts + 1;
	if (result.status === "pass") {
		return { ...state, phase: "review", attempts, lastVerification: result, lastFingerprint: result.fingerprint, lastFailure: undefined, unchangedFailureStreak: 0,
			workItems: state.workItems.map((item) => item.source === "godot_failure" && item.status === "reported_complete" ? { ...item, status: "closed" } : item) };
	}
	const signature = createHash("sha256").update(JSON.stringify(result.errors.map((error) => [error.stage, error.file, error.line, error.message]))).digest("hex");
	const sameFailure = state.lastFailure === signature;
	const unchangedFailureStreak = sameFailure ? (state.unchangedFailureStreak ?? 0) + 1 : 0;
	const phase: Phase = sameFailure && (state.lastFingerprint === result.fingerprint || unchangedFailureStreak >= 2) ? "stopped" : "plan";
	const failureItems: WorkItem[] = result.errors.map((error, index) => ({
		id: `E${attempts}-${index + 1}`, goal: error.message, source: "godot_failure", sourceId: `E${attempts}-${index + 1}`,
		doneWhen: `The observed ${error.stage} error no longer occurs.`, status: "active", originEvidence: error.message,
	}));
	return {
		...state,
		phase,
		attempts,
		lastFailure: signature,
		unchangedFailureStreak,
		lastFingerprint: result.fingerprint,
		lastVerification: result,
		lastFailureWorkIds: failureItems.map((item) => item.id),
		workItems: [...state.workItems, ...failureItems],
		plannerError: phase === "stopped" ? "The same Godot errors persisted after repeated revisions." : undefined,
	};
}

function nonempty(text: unknown, label: string): asserts text is string {
	if (typeof text !== "string" || !text.trim()) throw new Error(`${label} must be a nonempty string.`);
}

export function activeWorkset(state: TaskState): ActiveWorkset {
	if (state.phase !== "generate") throw new Error("An active workset is available only during generation.");
	const extras = (state.extraWorkIds ?? []).map((id) => {
		const item = state.workItems.find((candidate) => candidate.id === id);
		if (!item) throw new Error(`Unknown approved work item: ${id}.`);
		return { id, goal: item.goal };
	});
	if (state.pendingRequirements?.length) {
		return {
			source: "review",
			items: [...state.pendingRequirements.map((id) => {
				const requirement = state.requirements.find((item) => item.id === id);
				if (!requirement) throw new Error(`Unknown pending requirement: ${id}.`);
				return { id, goal: requirement.text };
			}), ...extras],
		};
	}
	if (state.plan.length) return { source: "planner", items: [...state.plan.map(({ id, goal }) => ({ id, goal })), ...extras] };
	return { source: "user", items: [
		...state.requirements.map(({ id, text }) => ({ id, goal: text })),
		...extras,
	] };
}

export function validateWorksetChecks(state: TaskState, checks: WorksetCheck[] | undefined, reopenRequirementId?: string): { workset: ActiveWorkset; unresolved: WorksetCheck[] } {
	let workset: ActiveWorkset;
	if (reopenRequirementId !== undefined) {
		if (state.phase !== "review") throw new Error("Reopen a requirement only after a successful verification.");
		const requirement = state.requirements.find((item) => item.id === reopenRequirementId);
		if (!requirement) throw new Error(`Unknown original requirement: ${reopenRequirementId}.`);
		workset = { source: "review", items: [{ id: requirement.id, goal: requirement.text }] };
	} else {
		workset = activeWorkset(state);
	}
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
	if (state.phase !== "plan" || state.lastVerification?.status !== "fail" || !state.lastFailureWorkIds?.length) {
		throw new Error("Planner requires an actual failed Godot verification recorded by the Controller.");
	}
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
	const defaultParent = state.lastFailureWorkIds?.[0];
	const children: WorkItem[] = subtasks.map((task) => {
		const parent = state.workItems.find((item) => item.id === (task.parentWorkItemId ?? defaultParent));
		if (!parent) throw new Error(`Planner subtask ${task.id} has no authorized parent work item.`);
		return { id: task.id, goal: task.goal, source: parent.source, sourceId: parent.sourceId,
			parentWorkItemId: parent.id, doneWhen: task.goal, status: "active", originEvidence: parent.originEvidence };
	});
	return { ...state, phase: "generate", plan: subtasks, planObjective: plan.objective, pendingRequirements: undefined,
		integrationChecks: undefined, solved: [], completionEvidence: undefined, plannerError: undefined,
		workItems: [...state.workItems.filter((item) => !children.some((child) => child.id === item.id)), ...children], extraWorkIds: [] };
}

export function validatePlanScope(state: TaskState, plan: DecompositionPlan): void {
	if (state.phase !== "plan" || state.lastVerification?.status !== "fail") {
		throw new Error("Planner scope review requires an actual failed Godot verification.");
	}
	if (plan.decision !== "revise") return;
	const allowed = new Set(state.lastFailureWorkIds ?? []);
	if (!allowed.size) throw new Error("Planner has no authorized work item to decompose.");
	for (const task of plan.subtasks ?? []) {
		if (!task.parentWorkItemId || !allowed.has(task.parentWorkItemId)) {
			throw new Error(`Planner subtask ${task.id} must reference a current authorized work item.`);
		}
	}
}

export function authorizeProposal(state: TaskState, proposal: WorkProposal, decision: ScopeDecision, reason: string): TaskState {
	if (state.phase !== "generate") throw new Error("Propose additional work only during active generation.");
	for (const [label, value] of Object.entries({ expected: proposal.expected, observed: proposal.observed,
		evidence: proposal.evidence, proposedGoal: proposal.proposedGoal, reason })) nonempty(value, label);
	const basis = proposal.basis === "user_requirement"
		? state.workItems.find((item) => item.id === proposal.sourceId && item.source === "user_requirement")
		: state.workItems.find((item) => item.id === proposal.sourceId && item.source === "godot_failure");
	if (!basis) throw new Error(`Unknown work source: ${proposal.sourceId}.`);
	if (decision !== "required") {
		return { ...state, suggestions: [...(state.suggestions ?? []), { proposal, decision, reason }] };
	}
	if (basis.status === "closed") throw new Error("A completed work item cannot be reopened by a Generator proposal.");
	const id = `W${state.workItems.filter((item) => item.id.startsWith("W")).length + 1}`;
	const item: WorkItem = { id, goal: proposal.proposedGoal,
		source: proposal.basis === "user_requirement" ? "requirement_gap" : "godot_failure",
		sourceId: basis.sourceId, parentWorkItemId: basis.id, doneWhen: proposal.expected,
		status: "active", originEvidence: `${proposal.observed} Evidence: ${proposal.evidence}` };
	return { ...state, workItems: [...state.workItems, item], extraWorkIds: [...(state.extraWorkIds ?? []), id] };
}

export function generatorHandoff(state: TaskState): string {
	if (state.phase !== "generate" || !state.plan.length) return "";
	const workset = activeWorkset(state);
	return `Generator plan: ${JSON.stringify({
		objective: state.planObjective ?? state.goal,
		subtasks: state.plan,
	})}\nCurrent ${workset.source} workset: ${workset.items.map((item) => `${item.id}: ${item.goal}`).join("; ")}. Complete the whole workset, then call godot_verify once with workset_checks for every ID. If an item is unresolved, continue only that item. Suggested files are hints, not a restriction on edits; do not add optional objectives.`;
}

export function recordCompletedWorkset(state: TaskState, checks: WorksetCheck[], fingerprint: string): TaskState {
	const { workset, unresolved } = validateWorksetChecks(state, checks);
	if (unresolved.length) throw new Error("Cannot record an incomplete workset as completed.");
	const completed = new Map(checks.map(({ id, evidence }) => [id, evidence]));
	return { ...state,
		workItems: state.workItems.map((item) => completed.has(item.id)
			? { ...item, status: "reported_complete", completionEvidence: completed.get(item.id) } : item),
		solved: workset.source === "planner" ? checks.map(({ id, evidence }) => ({ id, evidence, fingerprint })) : state.solved,
	};
}

export function finishTask(state: TaskState, checks: RequirementCheck[], fingerprint: string,
	gapDecisions?: Record<string, ScopeDecision>): TaskState {
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
	if (gapDecisions) {
		const uncertain = checks.filter((check) => check.status === "missing" && gapDecisions[check.id] === "uncertain");
		if (uncertain.length) return { ...state, phase: "stopped", completionEvidence: checks,
			plannerError: `The reported gap for ${uncertain.map((item) => item.id).join(", ")} could not be confirmed; manual review is required.` };
	}
	const reviewed = checks.map((check) => {
		if (check.status !== "missing" || !gapDecisions) return check;
		nonempty(check.expected, `Expected behavior for ${check.id}`);
		nonempty(check.observed, `Observed behavior for ${check.id}`);
		const decision = gapDecisions[check.id];
		if (!decision) throw new Error(`Missing scope decision for ${check.id}.`);
		if (decision === "optional") return { ...check, status: "implemented" as const,
			evidence: `${check.evidence} Scope review found the proposed change optional.` };
		return check;
	});
	const missing = reviewed.filter((check) => check.status === "missing").map((check) => check.id);
	const workItems = state.workItems.map((item) => item.source === "user_requirement"
		? { ...item, status: missing.includes(item.id) ? "active" as const : "closed" as const,
			completionEvidence: reviewed.find((check) => check.id === item.id)?.evidence }
		: item);
	if (missing.length) {
		const gaps: WorkItem[] = missing.map((id) => {
			const check = reviewed.find((item) => item.id === id)!;
			return { id: `G${state.attempts}-${id}`, goal: state.requirements.find((item) => item.id === id)!.text,
				source: "requirement_gap", sourceId: id, parentWorkItemId: id, doneWhen: check.expected ?? check.evidence,
				status: "active", originEvidence: `${check.observed ?? check.evidence} Evidence: ${check.evidence}` };
		});
		return { ...state, phase: "generate", plan: [], planObjective: undefined, solved: [], pendingRequirements: missing,
			completionEvidence: reviewed, workItems: [...workItems, ...gaps], extraWorkIds: [] };
	}
	return { ...state, phase: "done", pendingRequirements: [], completionEvidence: reviewed,
		workItems: workItems.map((item) => item.status === "reported_complete" ? { ...item, status: "closed" } : item) };
}
import { createHash } from "node:crypto";
