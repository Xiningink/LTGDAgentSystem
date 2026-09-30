# LTGD Agent System

LTGD（Low-Token Game Development）是一个面向 **Pi 的 Godot 游戏开发扩展**。用户在 Pi 对话中用自然语言描述游戏；扩展在 Pi 原有的编码能力之外，负责记录任务状态、检查生成的 Godot 工程，并在确认失败时安排定向修复。它不是独立的游戏生成程序，也不需要在本仓库放一份 Pi 源码。

## 思路与目标

LTGD 先让 Generator 完成一版可检查的工程，再由 Executor 用 Godot 和原始需求检查结果；只有发现具体错误或缺项，才调用短上下文 Planner 给出修复步骤。这样把模型调用集中在实际问题上，减少没有明确失败依据的规划和返工，同时保留基本的工程运行检查。

```text
Pi 中的自然语言需求
  → Generator 创建 Godot 工程并交出工程路径
  → Executor 检查主场景、导入和启动，再审查原始需求
  → 全部通过：完成
  → 确认失败：Planner 给出修复步骤 → Generator 修改 → Executor 复查
```

Generator、Executor、Planner 是扩展中的三个职责。需求审查是 Executor 的一个检查阶段。Godot 导入和启动通过，只说明工程能运行到相应阶段；自动审查不能替代人工试玩、画面检查或完整的玩法评测。流程与停止条件详见 [扩展说明](LTGDAgentSystem/README.md)。

## 准备环境

1. 在 Windows 上安装 Pi，并确认命令行能运行 `pi`。Pi 负责模型配置、登录和会话。
2. 按 [`Godot_Engine/README.md`](Godot_Engine/README.md) 下载 Godot 4.6.2 Windows 标准版，并把程序放在指定路径。引擎文件不随本仓库提交。
3. 如需使用共享素材，按 [`assets/README.md`](assets/README.md) 获取并放置素材。扩展要求生成过程不要修改 `assets/` 或 `Godot_Engine/`。

## 使用

可以先从 [`tasks/`](tasks/README.md) 挑一个示例。`horror-signal-lost/` 等同名原题保留了上游 GameCraft-Bench 面向 Linux 的 `/workspace/...` 路径和命令；在 Windows 上使用本仓库时，请参考对应的 `*_window/` 目录，它们是针对本地路径、Godot 命令和截图方式调整的版本。

要使用这些示例，先在 CMD 中进入仓库根目录，再运行启动脚本：

```cmd
cd /d C:\path\to\LTGDAgentSystem
LTGDAgentSystem\start.cmd
```

脚本实际执行的是 `pi --extension <仓库路径>\LTGDAgentSystem\godot-pat\index.ts`。进入 Pi 后，用自然语言描述需求；例如可以输入：“请参考 `tasks/horror-signal-lost_window/instruction.md`，在 `.\output\game` 制作这个游戏。”扩展会把提到的任务目录文件纳入需求审查。也可以自行描述游戏，不使用示例；用户指定输出目录时使用指定目录，否则在 Pi 当前工作目录创建 `game/`。一项游戏任务结束后，开启新的 Pi 会话处理下一项任务。

Generator 交出实际工程路径后，Executor 自动运行检查，结果保存在 Pi 会话中。输入 `/godot-status` 可查看当前阶段和最近一次 Godot 检查；工程路径绑定后，还可使用 `godot_inspect_project` 和 `godot_inspect_scene` 查看简要结构。

## 仓库内容

| 目录 | 内容与来源 |
| --- | --- |
| [`LTGDAgentSystem/`](LTGDAgentSystem/README.md) | Pi 扩展、启动脚本和扩展测试；这是插件主体。 |
| [`Godot_Engine/`](Godot_Engine/README.md) | 本地 Godot 4.6.2 的获取与放置说明；仓库不包含引擎程序。 |
| [`assets/`](assets/README.md) | 本地共享素材的获取与许可说明；仓库不包含素材库。 |
| [`tasks/`](tasks/README.md) | 用于开发与比较的任务说明，包括 GameCraft-Bench 原题及本地 Windows 适配版。 |
| [`tools/`](tools/README.md) | Godot 命令行参考和 Windows 截图辅助脚本。 |
| [`reports/`](reports/README.md) | LTGD 开发过程中使用的 Pi 用量导出工具说明。 |
| [`output/`](output/README.md) | 本地实验生成的游戏工程和用量导出结果；不是插件运行所必需的源码。 |

`assets/` 和 `Godot_Engine/` 是本地依赖；相邻的 `../GameEva/` 是迁移参考仓库。它们都不是 LTGD 扩展源码。各目录 README 说明了现有内容的来历和用途。
