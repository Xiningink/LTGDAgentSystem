# 任务说明的来源

这里保存用于 LTGD 开发和本地比较的游戏需求，不是插件运行时自动读取的任务队列。

| 目录 | 来历 |
| --- | --- |
| `horror-signal-lost/`、`puzzle-magnet-lab/`、`platformer-ivory-beats/` | [GameCraft-Bench](https://github.com/FreedomIntelligence/gamecraft-bench) 的原始任务说明。`instruction.md` 保留原题的 Linux 工作区路径与交付要求；`task.toml` 记录任务元数据。 |
| 对应的 `*_window/` | 基于同名任务制作的本地 Windows 适配版。游戏目标仍来自原题，工程路径、Godot 命令和截图步骤改为适配本工作区。 |

原题与适配版分目录保存，便于区分题目来源和本地改写。适配版用于本地运行、观察 LTGD 与直接生成的结果；它不是 GameCraft-Bench 官方评分器的输出。Godot 工程能导入、启动，也不等于玩法要求已经通过人工验证。

在 Windows 上试用时，从仓库根目录启动 Pi，然后在对话里引用对应的 `*_window/instruction.md`，例如 `tasks/horror-signal-lost_window/instruction.md`。上游同名目录用于查看原题；其中的 `/workspace/...` 路径和 Linux 命令不适合直接照搬到此工作区。
