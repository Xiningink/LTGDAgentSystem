# 本地实验输出的来源

这里保存开发 LTGD 时做的三组 Godot 游戏生成实验及对应的 Pi Token 用量导出。它们是实验产物，不是 Pi 插件源码。文件夹名中的 `direct` 表示直接使用 Pi 生成，`LTGD` 表示加载 LTGD 扩展后生成。

| 缩写 | 对应任务 | 生成工程 | 用量导出 |
| --- | --- | --- | --- |
| `HSL` | Horror Signal Lost | `game/HSL_direct/`、`game/HSL_LTGD/` | `token_usage/HSL_direct/`、`token_usage/HSL_LTGD/` |
| `MAG` | Puzzle Magnet Lab | `game/MAG_direct/`、`game/MAG_LTGD/` | `token_usage/MAG_direct/`、`token_usage/MAG_LTGD/` |
| `PIB` | Ivory Beats | `game/PIB_direct/`、`game/PIB_LTGD/` | `token_usage/PIB_direct/`、`token_usage/PIB_LTGD/` |

需求文本放在 [`../tasks/`](../tasks/README.md)。`game/` 是对应会话生成的工程目录；其中的资源来源和许可，以各工程已有的 README、CREDITS、ATTRIBUTION 或许可文件为准。`.godot/` 是 Godot 运行时生成的导入与编辑器缓存。

`token_usage/` 中的 `usage.md`、`usage.json`、`usage-per-call.csv`、`all-sessions.md` 和 `logs/` 来自 [`../reports/pi-token-usage/export_pi_usage.py`](../reports/pi-token-usage/export_pi_usage.py) 对本地 Pi 会话的导出。日志和报告可能包含对话内容、工具输出、本机路径与模型用量信息。这里的文件用于复查本地实验过程；它们不代表官方基准测试结果。
