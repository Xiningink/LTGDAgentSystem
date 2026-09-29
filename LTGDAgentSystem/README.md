# Godot-PaT extension

从希望作为工作目录的文件夹启动 Pi，进入后直接用自然语言描述需求。例如从仓库根目录启动：

```powershell
.\LTGDAgentSystem\start.ps1
```

`start.ps1` 和 `start.cmd` 都直接调用 `PiAgent/pi-test.ps1`，只额外加载 `godot-pat/index.ts`，并保留启动时的当前目录。扩展在编辑前调用一次 `godot_set_project`：用户指定了输出路径就使用该路径；未指定时在当前目录下创建 `game/`，把 `project.godot` 等工程文件放在其中。相对输出路径以 Pi 的当前目录为基准。`start.cmd` 保留窗口以显示错误。`PiAgent/.pi/` 中的扩展、skill 和提示词是 Pi 源码开发资源，正常制作游戏时不加载；这些文件仍保留在原处。模型和会话由 Pi 原脚本负责。

扩展提供 `godot_set_project`、`godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors`、失败后才可调用的 `godot_plan`，以及按顺序记录已验证子任务的 `godot_subtask_done`。Pi 的原生读写工具继续负责编辑。小任务直接尝试，大任务在同一轮中做简短里程碑草图；验证失败先局部修复，再失败才规划。相同文件和错误再次出现，或连续无进展，会停止自动重试。

验证在系统临时目录复制项目，跳过 `.godot`、`.git`、`.pi` 和 `node_modules`；运行 Godot 导入与无头启动，然后删除副本。精简报告和原始日志保存在顶层 `runs/`。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；这些仍需试玩或明确的任务检查。

`/godot-status` 查看当前阶段及最近一次验证。`runs/usage.jsonl` 记录 Pi 轮次 Token 用量和成本。运行需要 `PiAgent/node_modules` 中已有的 `tsx` 以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。
