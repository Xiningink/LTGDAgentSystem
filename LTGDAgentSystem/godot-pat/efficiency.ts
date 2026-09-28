import type { Phase } from "./controller.ts";

export function efficiencyInstruction(phase: Phase): string {
	if (phase === "repair" || phase === "plan" || phase === "stopped") return "";
	return `\n\n## LTGD generator efficiency\nUse only the analysis needed to choose the next action. Reuse established facts, then edit or call the relevant tool directly. Avoid repeating the same plan, tool output, or unchanged verification. Preserve complete code, requested features, and necessary gameplay and Godot checks; investigate fully when a new failure or ambiguity appears.`;
}
