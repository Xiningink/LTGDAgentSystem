# 任务目录

- `catch_001/`：已适配 GameEva 的可运行任务包，包含 `task.yaml`、`acceptance.yaml` 和冻结的 `verification/scenario.gd`。
- `puzzle-magnet-lab/`：GameCraft-Bench 原题 **Puzzle Magnet Lab**，原样保存 `instruction.md`、`task.toml`。
- `horror-signal-lost/`：GameCraft-Bench 原题 **Horror Signal Lost**，原样保存 `instruction.md`、`task.toml`。
- `keepsake/`：GameCraft-Bench 原题 **Keepsake**，原样保存 `instruction.md`、`task.toml`。

后三题保留原文，来源与哈希见 [筛选记录](../benchmarks/gamecraft_bench_selected/README.md)。它们现在可以作为自然语言输入直接生成，但含 Linux 路径且没有本地玩法评测，不宜直接用于 Windows 比较。对应的 `*_window/` 目录另存 Windows 技术适配版，每目录有 `instruction.md`、`task.toml`、`修改说明.md`；原文件不删除、不覆盖。

- `puzzle-magnet-lab_window/`、`horror-signal-lost_window/`、`keepsake_window/`：只替换 Windows 路径、Godot 命令及不可用的 Linux 截图工具说明；英文原题玩法与逐帧演示轨迹协议保留。各目录没有预置玩法断言或测试桥。生成时要求 Agent 自行提交演示轨迹；本地回放仅保存执行证据，不产生官方玩法分数。Godot 三门及回放通过仍记 `runnable_unverified`。

这些是 GameEva Windows 适配任务，不是上游 Harbor/多模态评分器的官方结果。
