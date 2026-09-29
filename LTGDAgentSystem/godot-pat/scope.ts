import type { Requirement, ScopeDecision, WorkProposal } from "./controller.ts";

export const SCOPE_SYSTEM_PROMPT = `You are LTGD's scope reviewer. Decide whether a proposed change is necessary to satisfy the original user requirement or to remove an observed Godot failure. Do not suggest new work. A possible improvement, subjective preference, or uncertain claim is not authorization. Return only JSON: {"decision":"required|optional|uncertain","reason":"one concrete sentence"}. Use required only when the supplied evidence demonstrates an unmet condition. Use uncertain when the evidence cannot establish that condition.`;

export function scopeInput(goal: string, requirement: Requirement | undefined, proposal: WorkProposal): string {
	return JSON.stringify({ original_request: goal, requirement: requirement ?? null, proposal });
}

export function parseScopeDecision(raw: string): { decision: ScopeDecision; reason: string } {
	const source = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
	let parsed: unknown;
	try { parsed = JSON.parse(source); }
	catch { throw new Error("Scope review must return JSON."); }
	if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Scope review must return an object.");
	const value = parsed as { decision?: unknown; reason?: unknown };
	if (!["required", "optional", "uncertain"].includes(String(value.decision)) || typeof value.reason !== "string" || !value.reason.trim()) {
		throw new Error("Scope review must contain a decision and reason.");
	}
	return { decision: value.decision as ScopeDecision, reason: value.reason };
}

export const PLAN_SCOPE_SYSTEM_PROMPT = `You are LTGD's plan scope reviewer. Each subtask must be necessary to resolve its referenced authorized work item. Return only JSON: {"decisions":[{"id":"subtask ID","decision":"required|optional|uncertain","reason":"one sentence"}]}. Do not approve optional polish or a task unsupported by its parent evidence. Uncertain does not authorize work.`;

export function parsePlanScopeDecisions(raw: string, ids: string[]): Record<string, ScopeDecision> {
	let parsed: unknown;
	try { parsed = JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")); }
	catch { throw new Error("Plan scope review must return JSON."); }
	if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as { decisions?: unknown }).decisions)) throw new Error("Plan scope review must return decisions.");
	const decisions = (parsed as { decisions: unknown[] }).decisions;
	if (decisions.length !== ids.length) throw new Error("Plan scope review must decide every subtask.");
	const result: Record<string, ScopeDecision> = {};
	for (const entry of decisions) {
		if (!entry || typeof entry !== "object") throw new Error("Invalid plan scope decision.");
		const item = entry as { id?: unknown; decision?: unknown; reason?: unknown };
		if (typeof item.id !== "string" || !ids.includes(item.id) || item.id in result ||
			!["required", "optional", "uncertain"].includes(String(item.decision)) || typeof item.reason !== "string" || !item.reason.trim()) {
			throw new Error("Invalid plan scope decision.");
		}
		result[item.id] = item.decision as ScopeDecision;
	}
	return result;
}
