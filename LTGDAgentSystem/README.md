# Godot-PaT extension

在要开发的 Godot 项目目录中运行下面的入口，进入 Pi 后直接用自然语言描述需求：

```powershell
cd games\system
..\..\LTGDAgentSystem\start.ps1
```

`start.ps1` 和 `start.cmd` 都直接调用 `PiAgent/pi-test.ps1`，只额外加载 `godot-pat/index.ts`。`PiAgent/.pi/` 中的扩展、skill 和提示词是 Pi 源码开发资源，正常制作游戏时不加载；这些文件仍保留在原处。`start.ps1` 从非游戏目录运行时默认进入 `games/system`，从其他 `games/<项目>` 目录运行时使用该项目。`start.cmd` 是双击入口，固定进入 `games/system` 并保留窗口显示错误。模型和会话由 Pi 原脚本负责。

扩展提供 `godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors`、失败后才可调用的 `godot_plan`，以及按顺序记录已验证子任务的 `godot_subtask_done`。Pi 的原生读写工具继续负责编辑。小任务直接尝试，大任务在同一轮中做简短里程碑草图；验证失败先局部修复，再失败才规划。相同文件和错误再次出现，或连续无进展，会停止自动重试。

验证在系统临时目录复制项目，跳过 `.godot`、`.git`、`.pi` 和 `node_modules`；运行 Godot 导入与无头启动，然后删除副本。精简报告和原始日志保存在顶层 `runs/`。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；这些仍需试玩或明确的任务检查。

`/godot-status` 查看当前阶段及最近一次验证。`runs/usage.jsonl` 记录 Pi 轮次 Token 用量和成本。运行需要 `PiAgent/node_modules` 中已有的 `tsx` 以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。
