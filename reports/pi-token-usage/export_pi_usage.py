#!/usr/bin/env python3
"""Export Pi session token usage and readable logs.

Reads the Pi agent session JSONL files (default: the current session from
$PI_SESSION_FILE, plus every other session under ~/.pi/agent/sessions) and
writes a token-usage report, a per-call CSV, a readable transcript and a copy
of the raw log under <out>/<session-id>/.

Usage:
    python export_pi_usage.py [--session <path.jsonl>] [--out <dir>]
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_OUT = Path(__file__).resolve().parent


# --------------------------------------------------------------------------- io


def session_files() -> list[Path]:
    root = Path.home() / ".pi" / "agent" / "sessions"
    if not root.is_dir():
        return []
    return sorted(root.rglob("*.jsonl"))


def read_records(path: Path):
    with path.open(encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                yield lineno, json.loads(line)
            except json.JSONDecodeError as exc:  # keep going on a torn line
                yield lineno, {"type": "_invalid", "error": str(exc)}


# ------------------------------------------------------------------- analysis


def parse_iso(ts):
    if ts is None:
        return None
    if isinstance(ts, (int, float)):
        # epoch milliseconds
        return datetime.fromtimestamp(ts / 1000.0, tz=timezone.utc)
    if not isinstance(ts, str):
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def part_text(part) -> str:
    if not isinstance(part, dict):
        return str(part)
    if part.get("type") == "text":
        return part.get("text", "") or ""
    if part.get("type") == "thinking":
        return part.get("thinking", "") or ""
    return ""


def analyse(path: Path) -> dict:
    """Collect everything we need from one session file."""
    info = {
        "path": path,
        "id": path.stem,
        "cwd": "",
        "provider": "",
        "model": "",
        "api": "",
        "start": None,
        "end": None,
        "records": 0,
        "invalid": 0,
        "roles": Counter(),
        "tools": Counter(),
        "calls": [],
        "messages": [],
        "errors": [],
        "custom": Counter(),
    }

    for _, rec in read_records(path):
        info["records"] += 1
        rtype = rec.get("type")

        if rtype == "_invalid":
            info["invalid"] += 1
            continue
        if rtype == "session":
            session_id = rec.get("id")
            if isinstance(session_id, str) and re.fullmatch(r"[A-Za-z0-9_-]+", session_id):
                info["id"] = session_id
            info["cwd"] = rec.get("cwd", "")
            info["start"] = parse_iso(rec.get("timestamp")) or info["start"]
            continue
        if rtype == "model_change":
            info["provider"] = rec.get("provider", info["provider"])
            info["model"] = rec.get("modelId", info["model"])
            continue
        if rtype == "custom":
            info["custom"][rec.get("customType", "?")] += 1
            continue
        if rtype != "message":
            continue

        msg = rec.get("message") or {}
        role = msg.get("role", "?")
        ts = parse_iso(msg.get("timestamp") or rec.get("timestamp"))
        if ts:
            info["start"] = ts if info["start"] is None else min(info["start"], ts)
            info["end"] = ts if info["end"] is None else max(info["end"], ts)
        info["roles"][role] += 1

        content = msg.get("content")
        parts = content if isinstance(content, list) else []
        texts = []
        tool_calls = []
        for part in parts:
            if not isinstance(part, dict):
                continue
            if part.get("type") == "toolCall":
                name = part.get("name", "?")
                tool_calls.append((name, part.get("arguments")))
                info["tools"][name] += 1
            else:
                t = part_text(part)
                if t:
                    texts.append(t)

        if role == "assistant":
            usage = msg.get("usage") or {}
            if usage:
                info["provider"] = msg.get("provider", info["provider"])
                info["model"] = msg.get("model", info["model"])
                info["api"] = msg.get("api", info["api"])
                cost = usage.get("cost") or {}
                info["calls"].append(
                    {
                        "timestamp": ts,
                        "input": int(usage.get("input", 0)),
                        "output": int(usage.get("output", 0)),
                        "reasoning": int(usage.get("reasoning", 0)),
                        "cache_read": int(usage.get("cacheRead", 0)),
                        "cache_write": int(usage.get("cacheWrite", 0)),
                        "total": int(usage.get("totalTokens", 0)),
                        "cost": float(cost.get("total", 0.0)),
                        "stop": msg.get("stopReason", ""),
                    }
                )
            if str(msg.get("stopReason", "")).lower() in {"error", "aborted"}:
                info["errors"].append(str(msg.get("stopReason")))

        if role in {"user", "assistant", "toolResult", "system"}:
            info["messages"].append(
                {
                    "role": role,
                    "timestamp": ts,
                    "texts": texts,
                    "tool_calls": tool_calls,
                    "has_usage": bool(msg.get("usage")),
                }
            )

    totals = {
        "calls": len(info["calls"]),
        "input": sum(c["input"] for c in info["calls"]),
        "output": sum(c["output"] for c in info["calls"]),
        "reasoning": sum(c["reasoning"] for c in info["calls"]),
        "cache_read": sum(c["cache_read"] for c in info["calls"]),
        "cache_write": sum(c["cache_write"] for c in info["calls"]),
        "total": sum(c["total"] for c in info["calls"]),
        "cost": sum(c["cost"] for c in info["calls"]),
    }
    totals["prompt"] = totals["input"] + totals["cache_read"] + totals["cache_write"]
    totals["peak_prompt"] = max(
        (c["input"] + c["cache_read"] + c["cache_write"] for c in info["calls"]),
        default=0,
    )
    duration = (info["end"] - info["start"]).total_seconds() if info["start"] and info["end"] else 0.0
    totals["duration_s"] = duration
    info["totals"] = totals
    return info


# -------------------------------------------------------------------- reports

TOOL_LABEL = {
    "read": "读取文件",
    "write": "写入文件",
    "edit": "编辑文件",
    "bash": "执行命令",
    "godot_set_project": "Godot 选择项目",
    "godot_inspect_project": "Godot 项目检查",
    "godot_inspect_scene": "Godot 场景检查",
    "godot_verify": "Godot 验证",
    "godot_get_errors": "Godot 读取错误",
    "godot_plan": "Godot 计划",
    "godot_subtask_done": "Godot 子任务完成",
    "godot_finish": "Godot 完成记录",
}


def human(n: int) -> str:
    return f"{n:,}"


def fmt_ts(ts: datetime | None) -> str:
    if ts is None:
        return "-"
    return ts.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def fmt_dur(seconds: float) -> str:
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h} 小时 {m} 分 {s} 秒"


def usage_markdown(info: dict) -> str:
    t = info["totals"]
    lines: list[str] = []
    lines.append(f"# Pi Token 用量报告 — 会话 `{info['id']}`\n")
    lines.append(f"- 会话文件: `{info['path']}`")
    lines.append(f"- 工作目录: `{info['cwd']}`")
    lines.append(f"- 模型: `{info['provider']} / {info['model']}` (api: `{info['api']}`)")
    lines.append(f"- 开始: {fmt_ts(info['start'])}")
    lines.append(f"- 结束: {fmt_ts(info['end'])}")
    lines.append(f"- 时长: {fmt_dur(t['duration_s'])}\n")

    lines.append("## 总览\n")
    lines.append("| 指标 | Tokens |")
    lines.append("| --- | ---: |")
    lines.append(f"| 输入 (input，未命中缓存) | {human(t['input'])} |")
    lines.append(f"| 缓存读取 (cacheRead) | {human(t['cache_read'])} |")
    lines.append(f"| 缓存写入 (cacheWrite) | {human(t['cache_write'])} |")
    lines.append(f"| **提示词合计 (prompt)** | **{human(t['prompt'])}** |")
    lines.append(f"| 输出 (output) | {human(t['output'])} |")
    lines.append(f"| 其中推理 (reasoning) | {human(t['reasoning'])} |")
    lines.append(f"| **总 Token（各次调用之和）** | **{human(t['total'])}** |")
    lines.append(f"| 单次最大提示词 | {human(t['peak_prompt'])} |")
    lines.append(f"| 模型调用次数 | {human(t['calls'])} |")
    lines.append(f"| 估算费用 (USD) | {t['cost']:.6f} |\n")

    cache_rate = (t["cache_read"] / t["prompt"] * 100.0) if t["prompt"] else 0.0
    lines.append(f"缓存命中率: **{cache_rate:.1f}%**（cacheRead / prompt）\n")
    if t["duration_s"] > 0:
        minutes = t["duration_s"] / 60.0
        lines.append(
            f"生成速度: **{t['output'] / minutes:.0f} output tokens/分钟**"
            f"（{t['output'] / t['duration_s']:.1f} tokens/秒，仅统计模型输出）\n"
        )
        lines.append(
            f"上下文吞吐: {t['prompt'] / minutes:.0f} prompt tokens/分钟"
            f"（包含重复发送的历史上下文与缓存读取，不代表计费工作量）\n"
        )

    # hourly breakdown
    hourly: dict[str, dict] = {}
    for c in info["calls"]:
        if not c["timestamp"]:
            continue
        key = c["timestamp"].astimezone(timezone.utc).strftime("%Y-%m-%d %H:00")
        h = hourly.setdefault(key, {"calls": 0, "prompt": 0, "output": 0, "total": 0, "cost": 0.0})
        h["calls"] += 1
        h["prompt"] += c["input"] + c["cache_read"] + c["cache_write"]
        h["output"] += c["output"]
        h["total"] += c["total"]
        h["cost"] += c["cost"]
    if hourly:
        lines.append("## 按小时分布\n")
        lines.append("| 小时 (UTC) | 调用次数 | prompt | output | total | 费用 USD |")
        lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
        for key in sorted(hourly):
            h = hourly[key]
            lines.append(
                f"| {key} | {h['calls']} | {human(h['prompt'])} | {human(h['output'])} | "
                f"{human(h['total'])} | {h['cost']:.6f} |"
            )
        lines.append("")

    # biggest prompt calls
    if info["calls"]:
        lines.append("## 提示词最大的 10 次调用\n")
        lines.append("| # | 时间 (UTC) | prompt | total | output |")
        lines.append("| ---: | --- | ---: | ---: | ---: |")
        ranked = sorted(
            enumerate(info["calls"], 1),
            key=lambda pair: pair[1]["input"] + pair[1]["cache_read"] + pair[1]["cache_write"],
            reverse=True,
        )[:10]
        for idx, c in ranked:
            prompt = c["input"] + c["cache_read"] + c["cache_write"]
            stamp = c["timestamp"].astimezone(timezone.utc).strftime("%m-%d %H:%M:%S") if c["timestamp"] else "-"
            lines.append(f"| {idx} | {stamp} | {human(prompt)} | {human(c['total'])} | {human(c['output'])} |")
        lines.append("")

    lines.append("## 消息与工具统计\n")
    lines.append("| 项目 | 数量 |")
    lines.append("| --- | ---: |")
    for role, count in sorted(info["roles"].items()):
        lines.append(f"| 消息 role={role} | {human(count)} |")
    lines.append(f"| 日志记录总数 | {human(info['records'])} |")
    if info["invalid"]:
        lines.append(f"| 解析失败行 | {human(info['invalid'])} |")
    lines.append("")

    if info["tools"]:
        lines.append("## 工具调用次数\n")
        lines.append("| 工具 | 次数 | 说明 |")
        lines.append("| --- | ---: | --- |")
        for name, count in info["tools"].most_common():
            lines.append(f"| `{name}` | {count} | {TOOL_LABEL.get(name, '')} |")
        lines.append("")

    if info["custom"]:
        lines.append("## 自定义记录\n")
        for name, count in info["custom"].most_common():
            lines.append(f"- `{name}`: {count}")
        lines.append("")

    lines.append("## 逐次调用明细\n")
    lines.append("| # | 时间 (UTC) | input | cacheRead | cacheWrite | prompt | output | reasoning | total | 费用 USD |")
    lines.append("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for i, c in enumerate(info["calls"], 1):
        prompt = c["input"] + c["cache_read"] + c["cache_write"]
        stamp = c["timestamp"].astimezone(timezone.utc).strftime("%H:%M:%S") if c["timestamp"] else "-"
        lines.append(
            f"| {i} | {stamp} | {human(c['input'])} | {human(c['cache_read'])} | "
            f"{human(c['cache_write'])} | {human(prompt)} | {human(c['output'])} | "
            f"{human(c['reasoning'])} | {human(c['total'])} | {c['cost']:.6f} |"
        )
    lines.append("")
    return "\n".join(lines)


def transcript_markdown(info: dict, tool_chars: int = 1200, text_chars: int = 4000) -> str:
    out: list[str] = []
    out.append(f"# 会话记录 `{info['id']}`\n")
    out.append(f"- 工作目录: `{info['cwd']}`")
    out.append(f"- 模型: `{info['provider']} / {info['model']}`")
    out.append(f"- 开始: {fmt_ts(info['start'])} / 结束: {fmt_ts(info['end'])}")
    out.append(f"- 消息条数: {len(info['messages'])}\n")
    out.append("> 工具输出已截断，完整内容见同目录下的原始 `.jsonl`。\n")
    out.append("---\n")

    role_label = {
        "system": "SYSTEM",
        "user": "USER",
        "assistant": "ASSISTANT",
        "toolResult": "TOOL",
    }
    for m in info["messages"]:
        stamp = m["timestamp"].astimezone(timezone.utc).strftime("%H:%M:%S") if m["timestamp"] else "--:--:--"
        out.append(f"## [{stamp}] {role_label.get(m['role'], m['role'])}\n")
        for name, args in m["tool_calls"]:
            try:
                arg_text = json.dumps(args, ensure_ascii=False)
            except TypeError:
                arg_text = str(args)
            if len(arg_text) > tool_chars:
                arg_text = arg_text[:tool_chars] + f" … (+{len(arg_text) - tool_chars} 字符)"
            out.append(f"**→ 调用工具 `{name}`**\n")
            out.append(f"```json\n{arg_text}\n```\n")
        for text in m["texts"]:
            body = text
            if len(body) > text_chars:
                body = body[:text_chars] + f"\n… (截断，共 {len(text)} 字符)"
            out.append(body)
            out.append("")
    return "\n".join(out)


def calls_csv_rows(info: dict):
    yield [
        "index",
        "timestamp",
        "input",
        "cache_read",
        "cache_write",
        "prompt",
        "output",
        "reasoning",
        "total",
        "cost_usd",
        "stop_reason",
    ]
    for i, c in enumerate(info["calls"], 1):
        yield [
            i,
            c["timestamp"].isoformat() if c["timestamp"] else "",
            c["input"],
            c["cache_read"],
            c["cache_write"],
            c["input"] + c["cache_read"] + c["cache_write"],
            c["output"],
            c["reasoning"],
            c["total"],
            f"{c['cost']:.8f}",
            c["stop"],
        ]


def all_sessions_markdown(infos: list[dict]) -> str:
    lines = ["# 所有 Pi 会话 Token 用量汇总\n"]
    lines.append("| 会话 | 开始 (UTC) | 目录 | 模型 | 调用次数 | prompt | output | total | 费用 USD |")
    lines.append("| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |")
    grand = {"prompt": 0, "output": 0, "total": 0, "cost": 0.0, "calls": 0}
    for info in sorted(infos, key=lambda i: i["start"] or datetime.min.replace(tzinfo=timezone.utc)):
        t = info["totals"]
        grand["prompt"] += t["prompt"]
        grand["output"] += t["output"]
        grand["total"] += t["total"]
        grand["cost"] += t["cost"]
        grand["calls"] += t["calls"]
        lines.append(
            f"| `{info['id'][:30]}…` | {fmt_ts(info['start'])} | {info['cwd']} | "
            f"{info['provider']}/{info['model']} | {t['calls']} | {human(t['prompt'])} | "
            f"{human(t['output'])} | {human(t['total'])} | {t['cost']:.6f} |"
        )
    lines.append(
        f"| **合计** | | | | {human(grand['calls'])} | {human(grand['prompt'])} | "
        f"{human(grand['output'])} | {human(grand['total'])} | {grand['cost']:.6f} |"
    )
    lines.append("")
    return "\n".join(lines)


# ----------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--session", default=os.environ.get("PI_SESSION_FILE", ""))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument(
        "--all-logs",
        action="store_true",
        help="同时导出其它会话的原始 jsonl 与可读转录",
    )
    args = ap.parse_args()

    primary = Path(args.session) if args.session else None
    if primary is None or not primary.is_file():
        found = session_files()
        if not found:
            print("找不到任何 Pi 会话日志。", file=sys.stderr)
            return 1
        primary = max(found, key=lambda p: p.stat().st_mtime)
        print(f"[warn] 未指定 --session，改用最新的会话: {primary}", file=sys.stderr)

    all_infos = [analyse(p) for p in session_files()]
    info = next((i for i in all_infos if i["path"] == primary), analyse(primary))
    out_dir = Path(args.out) / info["id"]
    logs_dir = out_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    # usage report + json + csv
    (out_dir / "usage.md").write_text(usage_markdown(info), encoding="utf-8")
    (out_dir / "usage.json").write_text(
        json.dumps(
            {
                "session_id": info["id"],
                "session_file": str(info["path"]),
                "cwd": info["cwd"],
                "provider": info["provider"],
                "model": info["model"],
                "api": info["api"],
                "start": info["start"].isoformat() if info["start"] else None,
                "end": info["end"].isoformat() if info["end"] else None,
                "totals": info["totals"],
                "roles": dict(info["roles"]),
                "tools": dict(info["tools"]),
                "custom": dict(info["custom"]),
                "calls": [
                    {
                        **{k: v for k, v in c.items() if k != "timestamp"},
                        "timestamp": c["timestamp"].isoformat() if c["timestamp"] else None,
                    }
                    for c in info["calls"]
                ],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    with (out_dir / "usage-per-call.csv").open("w", encoding="utf-8", newline="") as fh:
        csv.writer(fh).writerows(calls_csv_rows(info))

    # readable transcript + raw copy
    transcript_name = f"session-{info['id']}.md"
    (logs_dir / transcript_name).write_text(transcript_markdown(info), encoding="utf-8")
    raw_name = f"session-{info['id']}.jsonl"
    shutil.copy2(primary, logs_dir / raw_name)

    if args.all_logs:
        for other in all_infos:
            if other["path"] == primary:
                continue
            other_logs_dir = Path(args.out) / other["id"] / "logs"
            other_logs_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(other["path"], other_logs_dir / f"session-{other['id']}.jsonl")
            (other_logs_dir / f"session-{other['id']}.md").write_text(
                transcript_markdown(other), encoding="utf-8"
            )

    (out_dir / "all-sessions.md").write_text(all_sessions_markdown(all_infos), encoding="utf-8")

    t = info["totals"]
    print(f"会话: {info['id']}")
    print(f"  总 token        : {t['total']:,}")
    print(f"  提示词 (prompt) : {t['prompt']:,}  (input {t['input']:,} + cacheRead {t['cache_read']:,} + cacheWrite {t['cache_write']:,})")
    print(f"  输出 (output)   : {t['output']:,}  (含 reasoning {t['reasoning']:,})")
    print(f"  模型调用次数    : {t['calls']}")
    print(f"  费用估算 (USD)  : {t['cost']:.6f}")
    print(f"  时长            : {fmt_dur(t['duration_s'])}")
    print(f"导出目录: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
