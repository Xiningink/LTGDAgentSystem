# Godot-PaT extension

在要开发的 Godot 项目目录中运行下面的入口，进入 Pi 后直接用自然语言描述需求：

```powershell
cd games\system
..\..\LTGDAgentSystem\start.ps1
```

`start.ps1` 和 `start.cmd` 都直接调用 `PiAgent/pi-test.ps1`，只额外加载 `godot-pat/index.ts`。`PiAgent/.pi/` 中的扩展、skill 和提示词是 Pi 源码开发资源，正常制作游戏时不加载；这些文件仍保留在原处。`start.ps1` 从非游戏目录运行时默认进入 `games/system`，从其他 `games/<项目>` 目录运行时使用该项目。`start.cmd` 是双击入口，固定进入 `games/system` 并保留窗口显示错误。模型和会话由 Pi 原脚本负责。

扩展提供 `godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors`、失败后才可调用的 `godot_plan`、按顺序记录已验证子任务的 `godot_subtask_done`，以及最终记录完成证据的 `godot_finish`。Pi 的原生读写工具继续负责编辑。小任务直接尝试，大任务在同一轮中做简短里程碑草图；验证失败先局部修复，再失败才规划。相同文件和错误再次出现，或连续无进展，会停止自动重试。

验证在系统临时目录复制项目，跳过 `.godot`、`.git`、`.pi` 和 `node_modules`；运行 Godot 导入与无头启动，然后删除副本。精简报告和原始日志保存在顶层 `runs/`。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；任务此时进入 `verified`。检查需求并记录具体证据后，才能调用 `godot_finish` 进入 `done`。完成工具要求当前文件与最近一次通过验证的文件指纹一致，且计划子任务均已记录；这些条件仍不能替代真实试玩。

`/godot-status` 查看当前阶段及最近一次验证。`runs/usage.jsonl` 记录 Pi 轮次 Token 用量和成本。运行需要 `PiAgent/node_modules` 中已有的 `tsx` 以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。

完整游戏任务的首次模型请求不注入效率提示，保留初始设计空间。随后 `direct`、`execute_plan`、`verified` 使用短 `concise` 提示；首次失败后的 `repair` 使用针对最近错误的 `diagnose`；`plan`、`done`、`stopped` 不注入效率提示。再次修复失败仍按 PaT 规则进入规划。扩展在每次模型调用前替换同一个系统提示节，不会逐轮追加到会话历史；模型请求仍会重传当前短提示。`done` 和 `stopped` 允许一次正常收尾回复，扩展不会再自动触发后续任务轮次，也不会调整模型的 thinking level。

在启动前设置 `LTGD_EFFICIENCY_PROMPT=off` 可关闭动态提示，作为未来对照组。`runs/usage.jsonl` 记录每轮实际 `policyMode`（`concise`、`diagnose` 或 `none`）、是否注入提示、模型及提供方报告的 reasoning Token；旧记录仍可保留。`reasoning: null` 表示提供方未报告该项，且 reasoning 已包含在 `output` 中，不应重复加总。当前仅验证机制和状态切换，尚未运行付费模型对照，不能据此断言 Token 已下降。
