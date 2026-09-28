"""Build the LTGD technical report from reviewed workspace evidence."""

from __future__ import annotations

import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "reports" / "LTGD_Technical_Report.docx"
FONT_PATH = Path("C:/Windows/Fonts/arial.ttf")
FONT_BOLD_PATH = Path("C:/Windows/Fonts/arialbd.ttf")
NAVY = (30, 59, 88)
PALE = (235, 242, 248)
LIGHT = (246, 248, 250)
DARK = (28, 36, 44)
GRAY = (94, 105, 116)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_BOLD_PATH if bold else FONT_PATH), size)


def centered(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], lines: list[str],
             size: int, bold: bool = False, color: tuple[int, int, int] = DARK) -> None:
    x0, y0, x1, y1 = xy
    ft = font(size, bold)
    step = int(size * 1.25)
    height = step * len(lines)
    y = (y0 + y1 - height) // 2
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=ft)
        width = bb[2] - bb[0]
        draw.text(((x0 + x1 - width) // 2, y), line, font=ft, fill=color)
        y += step


def box(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], title: str,
        lines: list[str], fill: tuple[int, int, int] = LIGHT) -> None:
    draw.rounded_rectangle(xy, radius=28, fill=fill, outline=NAVY, width=5)
    x0, y0, x1, y1 = xy
    draw.text((x0 + 30, y0 + 28), title, font=font(59, True), fill=NAVY)
    y = y0 + 108
    for line in lines:
        draw.text((x0 + 30, y), line, font=font(43), fill=DARK)
        y += 62


def arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int],
          label: str | None = None, label_pos: tuple[int, int] | None = None) -> None:
    draw.line([start, end], fill=NAVY, width=10)
    sx, sy = start
    ex, ey = end
    if ex > sx:
        pts = [(ex, ey), (ex - 35, ey - 20), (ex - 35, ey + 20)]
    elif ex < sx:
        pts = [(ex, ey), (ex + 35, ey - 20), (ex + 35, ey + 20)]
    elif ey > sy:
        pts = [(ex, ey), (ex - 20, ey - 35), (ex + 20, ey - 35)]
    else:
        pts = [(ex, ey), (ex - 20, ey + 35), (ex + 20, ey + 35)]
    draw.polygon(pts, fill=NAVY)
    if label and label_pos:
        draw.text(label_pos, label, font=font(40, True), fill=NAVY)


def architecture_figure(target: Path) -> None:
    im = Image.new("RGB", (2600, 1150), "white")
    d = ImageDraw.Draw(im)
    box(d, (70, 85, 510, 340), "User request", ["Natural language", "in Pi conversation"], PALE)
    box(d, (680, 85, 1300, 395), "Pi runtime", ["Model and session", "Native read / edit / shell", "Conversation interface"], PALE)
    box(d, (1490, 85, 2530, 395), "Game project", ["Godot scenes, scripts and local assets", "Default workspace: games/system", "Explicit delivery may require copying"], LIGHT)
    box(d, (680, 550, 1300, 1055), "LTGD extension", ["Phase state in Pi session", "Compact project inspection", "Phase specific guidance", "Per-turn usage ledger", "Verify and plan tools"], LIGHT)
    box(d, (1490, 550, 2530, 795), "Isolated Godot check", ["Disposable project copy", "Import, then headless startup"], PALE)
    box(d, (1490, 900, 2530, 1080), "Evidence in runs", ["report.json, godot.log, usage.jsonl"], LIGHT)
    arrow(d, (510, 210), (680, 210))
    arrow(d, (1300, 240), (1490, 240))
    arrow(d, (990, 395), (990, 550))
    arrow(d, (1300, 995), (1490, 715))
    arrow(d, (2010, 795), (2010, 900))
    d.text((1515, 475), "Result returned through LTGD tool", font=font(42, True), fill=NAVY)
    im.save(target, dpi=(300, 300))


def workflow_figure(target: Path) -> None:
    im = Image.new("RGB", (2600, 1050), "white")
    d = ImageDraw.Draw(im)
    box(d, (65, 80, 570, 340), "Direct attempt", ["Pi edits the game", "without a planner"], PALE)
    box(d, (760, 80, 1260, 340), "Verify", ["Structure, import", "and headless boot"], LIGHT)
    box(d, (1450, 80, 1950, 340), "Verified", ["Import and boot", "passed"], PALE)
    box(d, (2110, 80, 2540, 340), "Finish gate", ["Agent evidence", "godot_finish to done"], LIGHT)
    box(d, (65, 620, 570, 930), "Stop", ["Repeated error, no", "progress or attempt cap"], LIGHT)
    box(d, (760, 620, 1260, 930), "Local repair", ["Fix the specific", "reported failure"], PALE)
    box(d, (1450, 620, 1950, 930), "Verify again", ["Same isolated", "Godot procedure"], LIGHT)
    box(d, (2110, 620, 2540, 930), "Plan and act", ["Ordered subtasks", "with checks"], PALE)
    arrow(d, (570, 210), (760, 210))
    arrow(d, (1260, 210), (1450, 210), "PASS", (1285, 145))
    arrow(d, (1950, 210), (2110, 210))
    arrow(d, (1010, 340), (1010, 620), "FAIL", (1035, 435))
    arrow(d, (1260, 775), (1450, 775))
    arrow(d, (1700, 620), (1700, 340), "PASS", (1730, 455))
    arrow(d, (1950, 775), (2110, 775), "FAIL", (1970, 710))
    arrow(d, (760, 775), (570, 775), "STOP", (615, 705))
    d.line([(2300, 930), (2300, 990), (1700, 990)], fill=NAVY, width=10)
    arrow(d, (1700, 990), (1700, 930))
    d.text((1840, 945), "Subtask loop", font=font(34, True), fill=NAVY)
    im.save(target, dpi=(300, 300))


def set_cell_fill(cell, color: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), color)
    tc_pr.append(shd)


def set_cell_border(cell) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    borders = tc_pr.first_child_found_in("w:tcBorders")
    if borders is None:
        borders = OxmlElement("w:tcBorders")
        tc_pr.append(borders)
    for side in ("top", "left", "bottom", "right"):
        node = OxmlElement(f"w:{side}")
        node.set(qn("w:val"), "single")
        node.set(qn("w:sz"), "4")
        node.set(qn("w:color"), "D9D9D9")
        borders.append(node)


def set_cell_margins(cell) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    mar = OxmlElement("w:tcMar")
    for side in ("top", "left", "bottom", "right"):
        node = OxmlElement(f"w:{side}")
        node.set(qn("w:w"), "105")
        node.set(qn("w:type"), "dxa")
        mar.append(node)
    tc_pr.append(mar)


def add_table(doc: Document, headers: list[str], rows: list[list[str]], widths: list[float] | None = None) -> None:
    table = doc.add_table(rows=1, cols=len(headers))
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    if widths:
        for i, width in enumerate(widths):
            table.columns[i].width = Inches(width)
    for j, heading in enumerate(headers):
        cell = table.rows[0].cells[j]
        cell.text = heading
        set_cell_fill(cell, "1E3B58")
        for run in cell.paragraphs[0].runs:
            run.font.bold = True
            run.font.color.rgb = RGBColor(255, 255, 255)
            run.font.size = Pt(9)
    table.rows[0]._tr.get_or_add_trPr().append(OxmlElement("w:tblHeader"))
    for i, data in enumerate(rows):
        cells = table.add_row().cells
        for j, value in enumerate(data):
            cells[j].text = value
            if i % 2 == 1:
                set_cell_fill(cells[j], "F0F5F9")
            for run in cells[j].paragraphs[0].runs:
                run.font.size = Pt(9)
    for row in table.rows:
        for j, cell in enumerate(row.cells):
            if widths:
                cell.width = Inches(widths[j])
            set_cell_border(cell)
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            for p in cell.paragraphs:
                p.paragraph_format.space_after = Pt(0)
                p.paragraph_format.line_spacing = 1.05
    doc.add_paragraph().paragraph_format.space_after = Pt(1)


def add_p(doc: Document, text: str, *, bold_start: str | None = None) -> None:
    p = doc.add_paragraph(style="Normal")
    if bold_start and text.startswith(bold_start):
        r = p.add_run(bold_start)
        r.bold = True
        p.add_run(text[len(bold_start):])
    else:
        p.add_run(text)


def add_bullet(doc: Document, text: str) -> None:
    p = doc.add_paragraph(style="List Bullet")
    p.add_run(text)


def add_fig(doc: Document, path: Path, caption: str) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.keep_with_next = True
    run = p.add_run()
    shape = run.add_picture(str(path), width=Inches(6.9))
    shape._inline.docPr.set("descr", caption)
    c = doc.add_paragraph(style="Caption")
    c.alignment = WD_ALIGN_PARAGRAPH.CENTER
    c.add_run(caption)


def setup(doc: Document) -> None:
    sec = doc.sections[0]
    sec.page_width = Inches(8.5)
    sec.page_height = Inches(11)
    sec.top_margin = Inches(0.8)
    sec.bottom_margin = Inches(0.75)
    sec.left_margin = Inches(0.82)
    sec.right_margin = Inches(0.82)
    normal = doc.styles["Normal"]
    normal.font.name = "Aptos"
    normal.font.size = Pt(10.6)
    normal.font.color.rgb = RGBColor(0, 0, 0)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.12
    for name, size, before, after in (("Title", 20, 0, 14), ("Heading 1", 14, 15, 7), ("Heading 2", 11.4, 10, 5)):
        style = doc.styles[name]
        style.font.name = "Aptos"
        style.font.size = Pt(size)
        style.font.bold = name != "Title"
        style.font.color.rgb = RGBColor(0, 0, 0)
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.keep_with_next = True
    title_ppr = doc.styles["Title"].element.get_or_add_pPr()
    for border in title_ppr.findall(qn("w:pBdr")):
        title_ppr.remove(border)
    cap = doc.styles["Caption"]
    cap.font.name = "Aptos"
    cap.font.size = Pt(8.8)
    cap.font.italic = True
    cap.font.color.rgb = RGBColor(75, 75, 75)
    cap.paragraph_format.space_after = Pt(10)
    doc.styles["List Bullet"].font.name = "Aptos"
    doc.styles["List Bullet"].font.size = Pt(10.6)
    foot = sec.footer.paragraphs[0]
    foot.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    foot.add_run("LTGD technical report  |  ")
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    foot._p.append(fld)
    for run in foot.runs:
        run.font.size = Pt(8)
        run.font.color.rgb = RGBColor(90, 90, 90)


def build() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ltgd-report-") as tmp:
        first = Path(tmp) / "architecture.png"
        second = Path(tmp) / "workflow.png"
        architecture_figure(first)
        workflow_figure(second)
        doc = Document()
        setup(doc)

        title = doc.add_paragraph(style="Title")
        title.add_run("A Pi Based Agent System for Godot Game Development")
        p = doc.add_paragraph()
        p.add_run("Technical report  |  Implementation snapshot 29 September 2026  |  Git revision 9640d5c")
        p.paragraph_format.space_after = Pt(14)

        doc.add_heading("Abstract", 1)
        add_p(doc, "This report documents the current LTGD Agent System, a Pi extension for developing Godot games from natural-language requests. Pi supplies the model session, conversation, and native file-editing tools; the LTGD extension adds compact project inspection, a bounded Planning-after-Trial-inspired controller, isolated Godot checks, and usage records. The controller first allows direct implementation, responds to a failed check with local repair, and exposes an explicit plan only after repair fails. A passing check advances to verified; a separate finish tool records the agent's textual requirement evidence before done. Neither step establishes playability independently. The report describes the implemented method and an evaluation protocol, then reserves its results section for future controlled runs. No claim of Token savings or benchmark performance follows from the current evidence. [E1-E5]")

        doc.add_heading("1 Problem and Motivation", 1)
        add_p(doc, "Natural-language game requests require a connected Godot project: scene files, scripts, resources, input behavior, and presentation must work together. A syntactically plausible script is therefore a weak completion criterion. GameCraft-Bench frames the task around engine grounding, complete artifacts, and observable interaction [2]. The local LTGD project uses this setting as motivation while limiting its present automated check to project structure, import, and headless startup. [E3, E6]")
        add_p(doc, "The research objective is to test whether a small amount of deterministic workflow control can improve development efficiency without constraining Pi's normal coding behavior. The current implementation places the user's request in the Pi conversation, lets Pi edit the game directly, and introduces a planner tool only after a failed direct attempt and a failed local repair. This is an adaptation of PaT's failure-triggered planning principle [1]; it is not a reproduction of PaT's original function-level experiments. [E1, E2]")
        add_p(doc, "Earlier GameEva material described a Python and LangGraph orchestration design. That material explains the migration rationale but is not the implementation assessed here. The current launcher loads one TypeScript extension into Pi; the repository retains the earlier design and task archives for provenance. [E5, E10]")

        doc.add_page_break()
        doc.add_heading("2 Design Basis and System Boundary", 1)
        add_p(doc, "PaT delays explicit planning until verification shows that a direct attempt was insufficient [1]. LTGD transfers that idea to a project-level Godot workflow: verification executes an engine, not a unit-test suite over a single function. Pi's extension API supports lifecycle hooks, model-callable tools, commands, and session entries [3]. LTGD uses those points to add control and evidence while leaving ordinary reads, writes, edits, and shell work to Pi. [E1, E2]")
        add_table(doc, ["Responsibility", "Implemented owner", "Concrete behavior"], [
            ["Conversation and editing", "Pi runtime", "Receives the user request; offers native read, write, edit and shell tools."],
            ["Workflow state", "LTGD extension", "Tracks direct, repair, plan, execute_plan, verified, done and stopped phases."],
            ["Technical verification", "LTGD plus Godot", "Checks structure, imports a disposable copy and performs headless startup."],
            ["Requirement judgement", "Human or future evaluator", "Inspects gameplay, visuals, task coverage and interaction quality."],
        ], [1.35, 1.3, 3.85])
        add_p(doc, "The division is deliberately narrow. The extension does not implement a separate Generator or Planner model process, does not edit Pi source, and does not score the GameCraft-Bench tasks with the upstream evaluator. Its plan phase is a tool and state transition inside the same Pi session. [E1, E2, E5, E6]")

        doc.add_heading("3 Architecture", 1)
        add_fig(doc, first, "Figure 1. Pi remains the conversation and editing runtime; LTGD adds control and evidence around an isolated Godot check. The check does not measure gameplay quality.")
        add_p(doc, "The PowerShell and CMD launchers invoke PiAgent/pi-test.ps1 with the LTGD index.ts extension. The PowerShell launcher preserves a current directory inside games/ and otherwise defaults to games/system; the CMD launcher starts at games/system. The active Pi working directory is also the root used by the extension's inspection and verification tools. These path rules matter when a user requests a different delivery directory. [E1, E5]")
        add_p(doc, "For each non-empty user input, the extension creates task state and records a fingerprint of the current project's Godot configuration, scenes, scripts, and shaders. It persists state as a Pi session entry and restores the active branch on session events. A compact project tool lists scenes and scripts; a scene tool extracts nodes, script references, and signal connections. The latter summarizes a scene without returning layout-heavy raw text. [E1, E4]")
        add_p(doc, "The extension observes model turns and appends provider-reported usage to runs/usage.jsonl. Its request-local system section has phase-specific guidance: the first full-game model request receives no efficiency instruction; later direct, execute_plan and verified work receives concise guidance; repair receives diagnostic guidance; plan, done and stopped receive none. LTGD_EFFICIENCY_PROMPT=off disables these additions. Current rows log the policy mode and whether guidance was active, but older rows lack those fields. [E1, E7]")

        doc.add_heading("4 Planning after Trial Method", 1)
        add_fig(doc, second, "Figure 2. Failure-triggered control flow. Import and headless startup yield verified, then godot_finish requires agent-supplied requirement evidence before done. Independent gameplay assessment remains outside this loop.")
        add_p(doc, "A new task begins in direct. Pi may sketch milestones for a large game request, then edit the project with its normal tools. Calling godot_verify checks for at least one scene and a configured main scene, copies the project into a temporary directory, runs a Godot editor import, and starts the copied game headlessly. The copy excludes .git, .godot, .pi, .pi-godot and node_modules. The original project is not modified by this verifier. [E1-E4]")
        add_p(doc, "On the first technical failure, the controller enters repair and asks for the smallest relevant fix. A second failed verification moves to plan, where write, edit and shell calls are blocked until godot_plan records one to six ordered subtasks. The agent then executes those subtasks sequentially. A subtask can advance only after a passing check of the current project fingerprint and a nonempty description of the requirement behavior the agent says it checked. This description is recorded evidence supplied by the agent; it is not an independent gameplay assertion. [E1, E2]")
        add_p(doc, "Repeated identical errors on the same source fingerprint, sustained lack of score improvement, or the verification-attempt cap moves the task to stopped. Infrastructure failures, such as a missing engine executable or a timeout, are reported separately and do not consume the ordinary task-attempt transition. A passing technical check moves an unplanned task to verified. The godot_finish tool reaches done only after all subtasks are complete, the passing check matches the current fingerprint, and the agent supplies nonempty requirement evidence. This is a textual completion gate, not an independent playtest. [E1-E3]")

        doc.add_heading("5 Implementation and Evidence", 1)
        doc.add_heading("5.1 Engine and output contract", 2)
        add_p(doc, "The verifier uses the local Godot 4.6.2 Windows console executable. Its structure check gives way to an editor import and then a bounded headless game run. It parses script and resource errors from Godot output, saves a compact report.json and full godot.log under a unique runs/ directory, and returns a file fingerprint with each result. The technical score distinguishes structure, import, and runtime stages only; it is not a game-quality score. [E3]")
        add_p(doc, "The Windows-adapted task packages preserve the English gameplay requests while replacing Linux paths and commands. They retain deterministic input-trace instructions, but the repository states that local replay saves logs rather than upstream video or official scoring. The Horror Signal Lost game in games/system contains a main scene, separate game-state and rendering scripts, and demo traces; a copy is present under output/AS/HorrorSignalLost. These artifacts provide an implementation case, not a controlled comparison. [E6, E8]")
        doc.add_heading("5.2 Tool and state interfaces", 2)
        add_table(doc, ["Pi callable tool", "Purpose and boundary"], [
            ["godot_inspect_project", "Lists the current directory's main scene, scenes, scripts and file count."],
            ["godot_inspect_scene", "Summarizes nodes, script links and signal connections in one scene."],
            ["godot_verify", "Runs structure, import and headless startup checks on a disposable copy."],
            ["godot_get_errors", "Returns the most recent compact verification result without running Godot."],
            ["godot_plan", "Accepts ordered subtasks only after direct work and repair have failed."],
            ["godot_subtask_done", "Records a verified project's current planned subtask with textual behavior evidence."],
            ["godot_finish", "Records task completion from verified with a current passing check and textual requirement evidence."],
        ], [2.05, 4.45])
        add_p(doc, "These operations expose narrow project facts and phase transitions. They do not replace Pi's file tools or determine the quality of a game design. The status command offers a concise view of phase and last verification to the human operator. [E1]")
        doc.add_heading("5.3 Audit trail", 2)
        add_p(doc, "Source-level tests cover phase transitions, the verified-to-done gate, prompt-mode switching, project and scene inspection, a disposable verification copy, and launcher loading. The runs directory contains verification reports, raw Godot logs, a usage ledger, and a readable Pi session transcript. The transcript can show how a failure led to repair and planning, while report.json links to the corresponding engine output. None of these files is a substitute for a frozen, multi-condition evaluation. [E3, E7, E9]")
        add_p(doc, "The current extension verifies the Pi working directory rather than an arbitrary project argument. In the documented case, an explicitly requested delivery path differed from that working directory, so the agent developed in games/system and copied the result afterward. A future formal evaluation must validate the delivered directory independently and retain the copy manifest. [E1, E7, E8]")

        doc.add_heading("6 Evaluation Protocol", 1)
        add_p(doc, "The proposed study isolates the effects of the workflow and the efficiency instruction. Before a run, freeze the Windows task text and hashes, starting Godot project, shared asset snapshot, Godot executable, model and provider, sampling configuration, per-run budget, and manual-review rubric. Start every condition from a clean copy of the same baseline. Store one run identifier with its prompt, git revision, model settings, project snapshot, verification outputs, and usage ledger. [E6, E7, E10]")
        add_table(doc, ["Condition", "Agent behavior", "Readiness"], [
            ["Direct OneShot", "One model generation of a complete project followed by the common verifier.", "Requires a dedicated runner and artifact writer."],
            ["Plain Pi", "Pi develops and repairs using its native tools; no LTGD extension.", "Requires a clean baseline launch and common evaluator."],
            ["Pi plus LTGD prompt off", "Current extension; LTGD_EFFICIENCY_PROMPT=off.", "Launcher exists; controlled run still pending."],
            ["Pi plus LTGD default", "Current extension with phase-dependent efficiency instruction.", "Launcher exists; controlled run still pending."],
        ], [1.45, 3.15, 1.9])
        add_p(doc, "All conditions must be judged by the same external acceptance procedure. Record technical validity (structure, import, startup) separately from requirement coverage, demonstrable interaction, visual presentation, and human playtesting. Report success over all attempted runs; do not remove failures from the denominator. Compare Token and cost among successful runs and across all runs, since a cheaper failure does not satisfy the task. The Direct OneShot runner and independent gameplay evaluator are future work, so their results must remain empty until implemented. [E3, E6, E10]")
        add_p(doc, "For model usage, preserve the provider's input, output, cache-read, cache-write, reasoning and currency-cost fields separately. Reasoning tokens are a subset of output when supplied and must not be added twice. Use a fixed provider/model and one accounting rule across conditions. Record elapsed wall time, model turns, planner use, verification attempts, stopped states, human interventions, and delivery-path checks. Missing fields stay missing; they are not estimated from conversation length. [E1, E7]")

        doc.add_page_break()
        doc.add_heading("7 Results Pending Controlled Runs", 1)
        add_p(doc, "This section is reserved for controlled observations. Blank cells are intentional. Fill them only from run-indexed evidence after the conditions and evaluator above have been executed; do not insert values from the development transcript or archived GameEva runs.")
        add_table(doc, ["Condition", "Run IDs", "Technical pass", "Gameplay / rubric", "Human review"], [
            ["Direct OneShot", "", "", "", ""],
            ["Plain Pi", "", "", "", ""],
            ["Pi plus LTGD prompt off", "", "", "", ""],
            ["Pi plus LTGD default", "", "", "", ""],
        ], [1.65, 0.95, 1.2, 1.45, 1.25])
        add_p(doc, "Table 3 insertion source: run manifest and frozen task hash; runs/<run-id>/report.json and godot.log for technical checks; independent gameplay rubric and signed playtest notes for interaction and quality. Preserve every failed run in the denominator.")
        add_table(doc, ["Condition", "Input", "Output", "Cache read / write", "Cost", "Elapsed"], [
            ["Direct OneShot", "", "", "", "", ""],
            ["Plain Pi", "", "", "", "", ""],
            ["Pi plus LTGD prompt off", "", "", "", "", ""],
            ["Pi plus LTGD default", "", "", "", "", ""],
        ], [1.6, 0.8, 0.8, 1.3, 0.9, 1.1])
        add_p(doc, "Table 4 insertion source: per-condition usage JSONL and provider billing records, reconciled by run ID; monotonic start and end timestamps for elapsed time. Add model-call and verification-attempt counts in the accompanying analysis.")
        add_p(doc, "Interpretation to insert after data collection: [Compare validity and gameplay outcomes first. Then compare all-run and successful-run Token and cost distributions. Identify failure modes, uncertainty, and any manual interventions. State whether the efficiency prompt changed quality before discussing savings.]")

        doc.add_page_break()
        doc.add_heading("8 Limitations and Threats to Validity", 1)
        add_bullet(doc, "Technical validity is narrow. The implemented verifier can show import and headless startup, but it does not replay input traces, inspect rendered frames, or score the requested mechanics. The finish gate requires agent-supplied text, which cannot independently establish gameplay completeness. [E1-E3, E6]")
        add_bullet(doc, "The extension is tied to the Pi working directory. A user-specified output path can diverge from the verified project; post-copy revalidation and artifact identity checks are required for trustworthy delivery claims. [E1, E7]")
        add_bullet(doc, "Agent-supplied subtask evidence is textual. The extension checks for a passing project fingerprint and a nonempty explanation, but it does not independently prove the described behavior. [E1, E2]")
        add_bullet(doc, "The controller has no explicit intent router: each nonempty user message starts a new task state. Natural conversation and iterative game feedback may therefore need clearer state handling. [E1]")
        add_bullet(doc, "Existing usage rows predate current prompt-mode fields, and the available game transcript is a development case rather than a matched control. The report cannot infer Token savings or quality effects from those records. [E1, E7]")
        add_bullet(doc, "Windows task adaptations are not official GameCraft-Bench runs. The local packages omit an independent gameplay scorer and the upstream multimodal judge. Results must be labelled local until the official evaluation is executed. [2, E6, E10]")
        add_p(doc, "Further threats include stochastic model outputs, cache behavior, different manual interventions, mutable assets or prompts, and unbalanced starting projects. The proposed run manifest and shared evaluator reduce these threats, but a result section should describe any remaining deviations rather than silently averaging them.")

        doc.add_heading("9 Conclusion", 1)
        add_p(doc, "The current LTGD system is a compact Pi extension that makes a Godot development loop observable and bounded. It retains Pi as the entry point, adds project-aware inspection and disposable technical verification, invokes explicit planning only after a failed repair, and separates technical verification from the agent's completion declaration. The architecture is implemented; its effect on game quality and Token cost has not yet been established by controlled comparison. The next evidence milestone is an independent gameplay evaluator and matched runs across the four defined conditions. [E1-E3, E6]")

        doc.add_page_break()
        doc.add_heading("References", 1)
        add_p(doc, "[1] Yoon, Y. et al. PaT: Planning-after-Trial for Efficient Test-Time Code Generation. ACL 2026. https://arxiv.org/abs/2605.07248")
        add_p(doc, "[2] Luo, T. et al. GameCraft-Bench: Can Agents Build Playable Games End-to-End in a Real Game Engine? arXiv:2606.17861, 2026. https://arxiv.org/abs/2606.17861")
        add_p(doc, "[3] Pi documentation. Extensions. https://pi.dev/docs/latest/extensions (accessed 29 September 2026).")

        doc.add_heading("Evidence Index", 1)
        add_p(doc, "Repository root: C:\\Research\\LTGDAgentSystem. Source revision: 9640d5c. Paths below are repository-relative. Archived material is identified separately to prevent it from being mistaken for the current implementation.")
        add_table(doc, ["ID", "Evidence", "Use in this report"], [
            ["E1", "LTGDAgentSystem/godot-pat/index.ts; efficiency.ts", "Pi hooks, tools, prompt mode, usage and working-directory behavior"],
            ["E2", "LTGDAgentSystem/godot-pat/controller.ts", "Phases, plan entry, stop conditions and subtask transition"],
            ["E3", "LTGDAgentSystem/godot-pat/godot.ts", "Disposable Godot verification and saved reports"],
            ["E4", "LTGDAgentSystem/godot-pat/project.ts", "Project fingerprints and compact inspection"],
            ["E5", "LTGDAgentSystem/start.ps1; start.cmd; README.md", "Launcher contract and runtime dependencies"],
            ["E6", "tasks/*_window/instruction.md; task.toml; modification notes", "Windows task and evaluator boundary"],
            ["E7", "runs/usage.jsonl; runs/*/report.json; runs/agent-transcripts", "Development evidence and logging limitations"],
            ["E8", "games/system/; output/AS/HorrorSignalLost/", "Example game source and delivered copy"],
            ["E9", "LTGDAgentSystem/tests/godot-pat.test.ts", "Source-level checks covered by tests"],
            ["E10", ".retired/docs/GameEva/Design.md; .retired/reports/technical_report_template.md", "Historical design and evaluation intent only"],
        ], [0.5, 2.7, 3.3])

        doc.save(OUTPUT)


if __name__ == "__main__":
    build()
