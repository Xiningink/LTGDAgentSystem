import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { Phase } from "./controller.ts";

export type EfficiencyMode = "concise" | "diagnose" | "none";

export function isFullGameTask(goal: string): boolean {
	return goal.length > 180 || /(?:完整.*游戏|制作.*游戏|开发.*游戏|做.*游戏|创建.*游戏|build.*game|create.*game|make.*game)/i.test(goal);
}

export function efficiencyMode(phase: Phase | null, firstFullGameRequest: boolean, enabled: boolean): EfficiencyMode {
	if (!enabled || !phase || firstFullGameRequest) return "none";
	if (phase === "repair") return "diagnose";
	if (phase === "direct" || phase === "execute_plan" || phase === "verified") return "concise";
	return "none";
}

export function efficiencyInstruction(mode: EfficiencyMode): string {
	if (mode === "concise") return "\n\n## LTGD efficiency: concise\nReason briefly. Reuse known context; avoid repeated analysis. Prefer direct tool actions. Keep complete code and required checks.";
	if (mode === "diagnose") return "\n\n## LTGD efficiency: diagnose\nDiagnose the latest verification failure before acting. Fix the likeliest cause with the smallest relevant change, then verify.";
	return "";
}

export function withEfficiencyInstruction(messages: AgentMessage[], mode: EfficiencyMode): AgentMessage[] | undefined {
	const leading = messages[0];
	if (leading?.role !== "system") return undefined;
	const instruction = efficiencyInstruction(mode);
	if (!instruction && !("ltgd_efficiency" in (leading.sections ?? {}))) return undefined;
	return [
		{ ...leading, sections: { ...leading.sections, ltgd_efficiency: instruction || null } },
		...messages.slice(1),
	];
}
