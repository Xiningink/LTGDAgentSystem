import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

const SKIP = new Set([".git", ".godot", ".pi", ".pi-godot", "node_modules"]);
const SOURCE = new Set([".gd", ".tscn", ".tres", ".gdshader"]);

export interface ProjectIndex {
	project: string;
	mainScene?: string;
	scenes: string[];
	scripts: string[];
	resources: number;
	fingerprint: string;
}

export async function listProjectFiles(root: string): Promise<string[]> {
	const files: string[] = [];
	async function visit(dir: string): Promise<void> {
		for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
			if (SKIP.has(entry.name) || entry.isSymbolicLink()) continue;
			const full = path.join(dir, entry.name);
			if (entry.isDirectory()) await visit(full);
			else if (entry.isFile()) files.push(path.relative(root, full).replaceAll("\\", "/"));
			if (files.length > 4000) throw new Error("Project has more than 4000 files; narrow the project root.");
		}
	}
	await visit(root);
	return files.sort();
}

export async function inspectProject(root: string): Promise<ProjectIndex> {
	const files = await listProjectFiles(root);
	const hash = createHash("sha256");
	for (const name of files) {
		if (name === "project.godot" || SOURCE.has(path.extname(name))) {
			hash.update(name);
			hash.update(await fs.readFile(path.join(root, name)));
		}
	}
	const config = files.includes("project.godot") ? await fs.readFile(path.join(root, "project.godot"), "utf8") : "";
	const mainScene = config.match(/^run\/main_scene\s*=\s*"([^"]+)"/m)?.[1];
	return {
		project: root,
		mainScene,
		scenes: files.filter((file) => file.endsWith(".tscn")),
		scripts: files.filter((file) => file.endsWith(".gd")),
		resources: files.length,
		fingerprint: hash.digest("hex"),
	};
}

export async function inspectScene(root: string, relativePath: string): Promise<object> {
	const relative = relativePath.replace(/^res:\/\//, "").replaceAll("\\", "/");
	const full = path.resolve(root, relative);
	if (!relative.endsWith(".tscn") || (!full.startsWith(root + path.sep) && full !== root)) {
		throw new Error("Scene path must be a .tscn file inside the current project.");
	}
	const source = await fs.readFile(full, "utf8");
	const nodes = [...source.matchAll(/^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?/gm)]
		.slice(0, 100)
		.map((match) => ({ name: match[1], type: match[2], parent: match[3] ?? null }));
	const signals = [...source.matchAll(/^\[connection signal="([^"]+)" from="([^"]+)" to="([^"]+)" method="([^"]+)"/gm)]
		.slice(0, 100)
		.map((match) => ({ signal: match[1], from: match[2], to: match[3], method: match[4] }));
	const scripts = [...source.matchAll(/path="(res:\/\/[^\"]+\.gd)"/g)].map((match) => match[1]);
	return { scene: relative, root: nodes[0] ?? null, nodes, signals, scripts: [...new Set(scripts)] };
}
