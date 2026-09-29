import type { Requirement, RequirementSource } from "./controller.ts";

export const CONTRACT_EXTRACTION_PROMPT = `You establish the LTGD requirement contract before game generation. Extract every explicit deliverable, behavior, content, audio, visual, and technical condition from the supplied user request and task files. Treat candidate requirements as hints only; check the full sources independently. Split distinct obligations into separate items. Do not add optional improvements. Return only JSON: {"requirements":[{"text":"...","doneWhen":"observable completion condition","sourceEvidence":[{"sourceId":"exact source ID","quote":"exact short excerpt copied from that source"}]}]}. Every item needs a precise source quote. Do not summarize away a requirement.`;

export const CONTRACT_AUDIT_PROMPT = `Audit an LTGD requirement contract against every supplied source. Check each source from beginning to end for explicit requirements absent from the draft, including audio, visual, environmental, and ending requirements. Do not add optional improvements. Return only JSON: {"missing":[{"text":"...","doneWhen":"observable completion condition","sourceEvidence":[{"sourceId":"exact source ID","quote":"exact short excerpt copied from that source"}]}],"uncertain":false}. Return missing=[] only when every explicit obligation is covered. Set uncertain=true if you cannot determine completeness from the supplied sources.`;

function parseJson(raw: string): unknown {
	try { return JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")); }
	catch { throw new Error("Requirement contract review must return JSON."); }
}

export function parseContractItems(raw: string, key: "requirements" | "missing", sources: RequirementSource[]): Requirement[] {
	const parsed = parseJson(raw);
	if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Requirement contract review must return an object.");
	const value = parsed as Record<string, unknown>;
	if (key === "missing" && value.uncertain !== false) throw new Error("Requirement coverage audit could not confirm completeness.");
	if (!Array.isArray(value[key]) || (key === "requirements" && !value[key].length)) throw new Error(`Requirement contract needs a ${key} array.`);
	const sourceById = new Map(sources.map((source) => [source.id, source.text]));
	return value[key].map((entry: unknown, index: number) => {
		if (!entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error("Invalid requirement contract item.");
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

export function completeContract(extracted: Requirement[], missing: Requirement[]): Requirement[] {
	const combined = [...extracted, ...missing];
	const seen = new Set<string>();
	for (const item of combined) {
		const key = `${item.text.toLowerCase()}\n${item.doneWhen?.toLowerCase()}`;
		if (seen.has(key)) throw new Error("Requirement coverage audit returned a duplicate; completeness needs review.");
		seen.add(key);
	}
	return combined.map((item, index) => ({ ...item, id: `R${index + 1}` }));
}
