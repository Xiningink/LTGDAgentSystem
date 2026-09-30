# LTGD：用于 Pi 的 Godot 游戏开发扩展

LTGD（Low-Token Game Development）把 Planning-after-Trial（PaT）的“先尝试，再针对失败规划”思路用于 Godot 游戏开发。用户仍在 **Pi 对话**里提出需求，Pi 负责生成游戏；本目录的扩展负责在生成后检查工程，并在发现具体问题时安排修复。这样，首次生成成功的任务不必调用 Planner。

## 准备与启动

- 在 Windows 上安装 Pi，确保命令行可以运行 `pi`；模型配置和登录由 Pi 管理，不需要本地 `PiAgent/` 源码。
- 按 [`Godot_Engine/README.md`](../Godot_Engine/README.md) 放置 Godot 4.6.2 Windows 标准版。扩展当前使用 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`；引擎文件不包含在 Git 仓库中。
- 如需使用共享素材，按 [`assets/README.md`](../assets/README.md) 准备。Generator 可以读取素材，但不应修改共享的 `assets/` 或 `Godot_Engine/`。

从希望作为 Pi 工作目录的文件夹运行 [`start.cmd`](start.cmd)。要参考本仓库的 Windows 任务示例，可以先进入仓库根目录：

```cmd
cd /d C:\path\to\LTGDAgentSystem
LTGDAgentSystem\start.cmd
```

启动脚本调用已安装的 `pi`，并通过 `--extension` 加载 [`godot-pat/index.ts`](godot-pat/index.ts)。在新 Pi 会话中直接描述需求，例如：“请参考 `tasks/horror-signal-lost_windows/instruction.md`，在 `.\output\game` 制作这个游戏。”`tasks/*_windows/` 是对上游 Linux 任务说明的本地 Windows 适配版，详见 [`tasks/README.md`](../tasks/README.md)。如果未指定输出目录，Generator 应在 Pi 当前工作目录下创建 `game/`。

## 一次任务如何运行

1. **Generator 先生成。** 扩展把首条游戏需求记录为原始目标，提示 Pi 直接制作第一版 Godot 工程。首轮不启动单独的 Planner。
2. **Generator 交接路径。** 完成一轮后，Generator 需要主动结束回复，并在末尾写出 `<ltgd-project-path>实际工程目录</ltgd-project-path>`。扩展从回复中读取路径，确认其中有 `project.godot`。扩展不会强行打断仍在工作的 Generator，也不会猜测没有交接的工程位置。
3. **Executor 做本地检查。** 扩展先检查场景和主场景配置，再运行 Godot 无头导入和 60 帧启动。导入与启动各有时间限制；这些检查由本地程序执行，不消耗模型调用。
4. **Executor 审查需求。** 只有 Godot 检查通过后，扩展才发起独立模型审查，将原始目标、被引用的任务说明、当前工程结构和相关文件交给审查者，判断是否存在有证据的需求缺项。它读取工程证据，不会实际试玩游戏。
5. **按结果结束或修复。** 两项检查均通过则记录为 `done`。若发现可修复的 Godot 错误或明确缺项，扩展才调用 Planner。Planner 根据最新失败和精简工程证据给出步骤，Generator 只处理这些步骤，再交给 Executor 复查。基础设施无法运行、证据不足以支持工程内修复或修复后工程未改变等情况会停止并报告原因。

流程可概括为 `需求 → Generator → Executor〔Godot 检查 → 需求审查〕→ 完成`；确认失败时才进入 `Planner → Generator 修复 → Executor 复查`。Planner 和需求审查是**独立模型调用**；Godot 检查不是。Planner 不编辑工程，Executor 也不编辑工程。

## 状态、工具与边界

扩展将目标、阶段、工程路径和检查结果记录在 Pi 会话中。输入 `/godot-status` 可以查看当前阶段和最近一次 Godot 检查。首次交接工程路径后，`godot_inspect_project` 可返回简短的工程索引，`godot_inspect_scene` 可查看指定场景的节点、脚本引用和信号连接；它们主要供修复时按需使用。

工程文件指纹用于确认需求审查对应的是刚通过 Godot 检查的版本，并阻止对未变化的失败工程重复验证。Godot 导入和启动通过只能证明工程达到这些技术检查；独立需求审查基于源码和场景证据，不能证明实际画面、交互手感或所有玩法都经过人工验证。

当前交接边界仍主要依靠对 Generator 的提示：它需要自行判断何时完成、停止继续修改并报告有效路径。扩展没有自动发现工程或强制限定生成轮数。若它没有按要求交接，Executor 就无法开始正常验收。这是当前实现的限制。

## 已归档的用量对比

仓库中的三组 GameCraft-Bench 任务各保存了一次普通 Pi 生成和一次加载 LTGD 的 Pi 会话。下表根据 [`output/token_usage/`](../output/README.md) 的 `usage.json` 汇总；Total Token 包含未缓存输入、缓存读取、缓存写入和输出，推理 Token 已计入输出。

| 游戏 | 普通 Pi：调用 / Total Token | LTGD：调用 / Total Token | 本次 Token 用量降低 |
| --- | ---: | ---: | ---: |
| Horror Signal Lost | 171 / 32.891 M | 123 / 16.405 M | 50.1% |
| Puzzle Magnet Lab | 174 / 34.650 M | 138 / 19.466 M | 43.8% |
| Ivory Beats | 73 / 8.268 M | 53 / 5.121 M | 38.1% |

这些是每种条件各一次的历史运行结果，没有重复试验，也没有统一的玩法质量分数。它们说明这六次会话的用量差异，不能证明 LTGD 在同等游戏质量下稳定节省上述比例的 Token；需求审查和失败后的修复也会产生额外模型开销。

## 可选的画面检查

自动流程不包含实际画面验收。需要截图时，可以从仓库根目录使用 [`tools/screenshot.ps1`](../tools/screenshot.ps1)。脚本已移动到顶层 `tools/`，因此当前布局下须显式传入 `-Godot`：

```powershell
.\tools\screenshot.ps1 -Project .\output\game\HSL_LTGD -Out .\frame.png -Frames 30 -Godot .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe
```

请把 `-Project` 换成实际游戏工程目录。截图脚本使用图形驱动运行 Godot；不能使用 `--headless` 截取 viewport。更多参数见 [`tools/README.md`](../tools/README.md)。
