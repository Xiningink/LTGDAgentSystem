import type { Phase } from "./controller.ts";

export function efficiencyInstruction(phase: Phase): string {
	if (phase === "repair" || phase === "plan" || phase === "stopped") return "";
	return `\n\n## LTGD generator efficiency\nUse only reasoning that changes the next action. Reuse settled facts; avoid duplicate checks. Keep complete code and required verification. Analyze new failures fully.`;
}
