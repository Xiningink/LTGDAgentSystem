# 任务目录

- `catch_001/`：已适配 GameEva 的可运行任务包，包含 `task.yaml`、`acceptance.yaml` 和冻结的 `verification/scenario.gd`。
- `puzzle-magnet-lab/`：GameCraft-Bench 原题 **Puzzle Magnet Lab**，原样保存 `instruction.md`、`task.toml`。
- `horror-signal-lost/`：GameCraft-Bench 原题 **Horror Signal Lost**，原样保存 `instruction.md`、`task.toml`。
- `keepsake/`：GameCraft-Bench 原题 **Keepsake**，原样保存 `instruction.md`、`task.toml`。
- `racing-trick-runner/`：GameCraft-Bench 原题 **Racing Trick Runner**，原样保存 `instruction.md`、`task.toml`。

前三题保留原文，来源与哈希见 [筛选记录](../benchmarks/gamecraft_bench_selected/README.md)。新增的 `racing-trick-runner/` 也保留原文，其来源与哈希见对应 `*_window/修改说明.md`。这些原题含 Linux 路径且没有本地玩法评测，不宜直接用于 Windows 比较。对应的 `*_window/` 目录另存 Windows 技术适配版，每目录有 `instruction.md`、`task.toml`、`修改说明.md`；原文件不删除、不覆盖。

- `puzzle-magnet-lab_window/`、`horror-signal-lost_window/`、`keepsake_window/`、`racing-trick-runner_window/`：供 Windows 游戏开发使用，保留英文原题的玩法要求，适配本地路径和 Godot 命令，并移除 Demo 轨迹交付要求。各目录没有预置玩法断言或测试桥；Godot 导入与启动通过只说明工程可运行，玩法仍需试玩。

这些是 GameEva Windows 适配任务，不是上游 Harbor/多模态评分器的官方结果。
