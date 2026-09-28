import type { Phase } from "./controller.ts";

export function efficiencyInstruction(phase: Phase): string {
	if (phase === "stopped") return "";
	if (phase === "repair" || phase === "plan") {
		return `\n- Reasoning efficiency: focus on the unresolved failure and the evidence needed to distinguish its causes. Reuse conclusions already established; do not repeat unchanged checks. Investigate as deeply as needed to fix the failure and verify the repair.`;
	}
	return `\n- Reasoning efficiency: use only the analysis needed to choose the next action. Reuse established facts, then edit or call the relevant tool directly. Avoid repeating the same plan, tool output, or unchanged verification. Preserve complete code, requested features, and necessary gameplay and Godot checks; investigate fully when a new failure or ambiguity appears.`;
}
