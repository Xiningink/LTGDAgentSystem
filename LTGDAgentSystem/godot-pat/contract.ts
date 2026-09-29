import type { Requirement, RequirementSource } from "./controller.ts";

export const CONTRACT_EXTRACTION_PROMPT = `Create a compact contract for the game that must be delivered, using the supplied user request and task files. Extract all required player-facing behavior, content, audio, visuals, and game-specific delivery conditions. Group details of the same feature into one requirement, with a doneWhen that covers those details; do not make one item per sentence or per adjective. Keep distinct features separate. Treat broad quality goals as one condition, not as a reason to invent extra polish work.

Do not turn instructions for the agent or LTGD workflow into game requirements: reading files, selecting paths, calling tools, browsing/copying assets, running checks, and manual playtesting are process steps. Asset availability and example commands are context. Runner metadata in task.toml (timeouts, CPU, memory, storage, GPU, OS, internet, schema, authors) is not a game feature. The Controller already selects the output directory and verifies Godot startup. Candidate requirements are hints only; read the full sources. Do not add optional improvements.

Return only JSON: {"requirements":[{"text":"...","doneWhen":"observable completion condition","sourceEvidence":[{"sourceId":"exact source ID","quote":"exact short excerpt copied from that source"}]}]}. Every item needs at least one short, exact source quote. Use multiple sourceEvidence entries if needed to support grouped details.`;

export function parseContractItems(raw: string, sources: RequirementSource[]): Requirement[] {
	let parsed: unknown;
	try { parsed = JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")); }
	catch { throw new Error("Requirement extraction must return JSON."); }
	if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Requirement extraction must return an object.");
	const items = (parsed as { requirements?: unknown }).requirements;
	if (!Array.isArray(items) || !items.length) throw new Error("Requirement extraction needs a nonempty requirements array.");
	const sourceById = new Map(sources.map((source) => [source.id, source.text]));
	return items.map((entry: unknown, index: number) => {
		if (!entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error("Invalid requirement item.");
		const item = entry as Record<string, unknown>;
		if (typeof item.text !== "string" || !item.text.trim() || typeof item.doneWhen !== "string" || !item.doneWhen.trim()) {
			throw new Error("Every requirement needs text and a completion condition.");
		}
		if (!Array.isArray(item.sourceEvidence) || !item.sourceEvidence.length) throw new Error("Every requirement needs source evidence.");
		const sourceEvidence = item.sourceEvidence.map((evidence: unknown) => {
			if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) throw new Error("Invalid requirement source evidence.");
			const ref = evidence as Record<string, unknown>;
			if (typeof ref.sourceId !== "string" || typeof ref.quote !== "string" || !ref.quote.trim() ||
				!sourceById.get(ref.sourceId)?.includes(ref.quote)) throw new Error("Requirement quote must match a supplied source exactly.");
			return { sourceId: ref.sourceId, quote: ref.quote };
		});
		return { id: `R${index + 1}`, text: item.text.trim(), doneWhen: item.doneWhen.trim(), sourceEvidence };
	});
}
