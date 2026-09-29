# Godot-PaT extension

在希望作为工作目录的文件夹中运行入口；例如从仓库根目录启动：

```powershell
.\LTGDAgentSystem\start.ps1
```

`start.ps1` 和 `start.cmd` 都直接调用 `PiAgent/pi-test.ps1`，只额外加载 `godot-pat/index.ts`。两个入口都保持启动时的当前目录，不创建默认游戏目录。用户未指定项目路径时，该目录就是 Godot 项目目录；若任务指定了交付目录，应直接在那里创建游戏，并先调用 `godot_set_project`，使检查和验证指向同一目录。相对路径以 Pi 启动时的当前目录为基准。`start.cmd` 保留窗口以显示错误。`PiAgent/.pi/` 中的扩展、skill 和提示词是 Pi 源码开发资源，正常制作游戏时不加载；这些文件仍保留在原处。模型和会话由 Pi 原脚本负责。

扩展提供设置实际项目路径的 `godot_set_project`、`godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors`、失败后才可调用的 `godot_plan`，以及按顺序记录已验证子任务的 `godot_subtask_done`。Pi 的原生读写工具继续负责编辑。小任务直接尝试，大任务在同一轮中做简短里程碑草图；验证失败先局部修复，再失败才规划。相同文件和错误再次出现，或连续无进展，会停止自动重试。

验证在系统临时目录复制项目，跳过 `.godot`、`.git`、`.pi` 和 `node_modules`；运行 Godot 导入与无头启动，然后删除副本。精简报告和原始日志保存在顶层 `runs/`。`PASS` 使 PaT 任务进入 `done`，但它只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；这些仍需试玩或明确的任务检查。

`/godot-status` 查看当前阶段及最近一次验证。`runs/usage.jsonl` 记录 Pi 轮次 Token 用量和成本。运行需要 `PiAgent/node_modules` 中已有的 `tsx` 以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。

动态精简提示试验已回退到加入该策略前的 PaT 行为；扩展不再按阶段注入 `concise` 或 `diagnose` 提示，也不改变模型的 thinking level。已有的 `runs/usage.jsonl` 历史记录保留，新记录使用原来的基础用量字段。运行中的 Pi 进程需要重启，才能加载回退后的扩展。
