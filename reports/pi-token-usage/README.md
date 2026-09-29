# Pi Token 用量与日志导出

本目录是一次 `pi` 运行（Horror Signal Lost 游戏生成任务）的 token 统计与日志导出。

## 结论速览

本次会话（Horror Signal Lost 生成任务，`deepseek-flash`，截至 2026-09-29 06:17 UTC）：

| 指标 | 数值 |
| --- | ---: |
| 会话 ID | `2026-09-29T05-59-32-794Z_01a0ebbf` |
| 总 Token（各次模型调用之和） | 9,797,019 |
| 提示词合计 (prompt) | 9,670,951 |
| ├ 未命中缓存输入 (input) | 190,247 |
| ├ 缓存读取 (cacheRead) | 9,480,704 |
| └ 缓存写入 (cacheWrite) | 0 |
| 输出 (output) | 126,068 |
| └ 其中推理 (reasoning) | 72,535 |
| 模型调用次数 | 100 |
| 缓存命中率 | 98.0% |
| 单次最大提示词 | 157,682 |
| 估算费用 | 0.2652 USD |
| 会话时长 | 约 18 分 11 秒 |

> 数字会随会话继续进行而增长；执行 `python export_pi_usage.py` 可刷新为最新值。
> 本机全部 12 个会话合计：**63,057,877 token / 632 次调用 / 2.0322 USD**（见 `all-sessions.md`）。

## 文件说明

| 文件 | 内容 |
| --- | --- |
| `usage.md` | **主报告**：总览、按小时分布、最大 prompt 调用、消息/工具统计、逐次调用明细 |
| `usage.json` | 同一份数据的机器可读版本（含每次调用的原始 usage 字段） |
| `usage-per-call.csv` | 每次模型调用的 input / cacheRead / output / total / cost，便于用 Excel 透视 |
| `all-sessions.md` | 本机所有 pi 会话的用量汇总与合计 |
| `logs/session-<id>.jsonl` | 原始会话日志（不可读，数据源） |
| `logs/session-<id>.md` | 可读对话转录（工具输出截断） |
| `export_pi_usage.py` | 生成以上所有文件的脚本 |

`logs/` 因体积较大被 `.gitignore` 排除，但文件已存在于本地磁盘。

## 重新生成

```bash
python reports/pi-token-usage/export_pi_usage.py            # 当前/最新会话
python reports/pi-token-usage/export_pi_usage.py --all-logs # 连同其它会话原始日志
python reports/pi-token-usage/export_pi_usage.py --session "C:\path\to\session.jsonl"
```

数据来源：`%USERPROFILE%\.pi\agent\sessions\**\*.jsonl` 中每条 `assistant`
消息的 `message.usage` 字段（`input` / `output` / `cacheRead` / `cacheWrite` /
`reasoning` / `totalTokens` / `cost`）。

## 口径说明

- `totalTokens = input + output + cacheRead + cacheWrite`，即一次 API 调用计入的全部 token。
  `reasoning` 是 `output` 的子集，不重复计算。
- **总 Token 是多次调用的累加**：每一轮对话都会重新发送全部历史上下文，因此
  prompt 会随会话推进持续增长（本会话峰值约 23.7 万 prompt tokens/次）。
- `cacheRead` 指命中服务端 prompt cache 的历史上下文，单价远低于普通 input，
  这也是缓存命中率高达 98.7% 而总费用仅约 0.44 USD 的原因。
