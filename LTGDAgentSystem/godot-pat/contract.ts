import type { Requirement, RequirementSource } from "./controller.ts";

export const CONTRACT_EXTRACTION_PROMPT = `Extract every explicit game requirement from the supplied user request and task files. Include behavior, content, audio, visual, and technical conditions. Split distinct obligations into separate items. Candidate requirements are hints only; read the full sources. Do not add optional improvements. Return only JSON: {"requirements":[{"text":"...","doneWhen":"observable completion condition","sourceEvidence":[{"sourceId":"exact source ID","quote":"exact short excerpt copied from that source"}]}]}. Every item needs an exact source quote.`;

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
