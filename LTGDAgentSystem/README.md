# Godot-PaT extension

从希望作为工作目录的文件夹启动 Pi，进入后直接用自然语言描述需求。例如从仓库根目录启动：

```powershell
.\LTGDAgentSystem\start.ps1
```

`start.ps1` 和 `start.cmd` 都直接调用 `PiAgent/pi-test.ps1`，只额外加载 `godot-pat/index.ts`，并保留启动时的当前目录。扩展在编辑前调用一次 `godot_set_project`：用户指定了输出路径就使用该路径；未指定时在当前目录下创建 `game/`，把 `project.godot` 等工程文件放在其中。相对输出路径以 Pi 的当前目录为基准。`start.cmd` 保留窗口以显示错误。`PiAgent/.pi/` 中的扩展、skill 和提示词是 Pi 源码开发资源，正常制作游戏时不加载；这些文件仍保留在原处。模型和会话由 Pi 原脚本负责。

扩展提供 `godot_set_project`、`godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors` 和最终的 `godot_finish`。Pi 的原生读写工具继续负责编辑。主流程是 Generator 制作游戏 → Godot 验证；验证失败时调用 Planner；Generator 根据整份计划修改后统一验证；验证通过再检查原始需求并总结。同一工程指纹和同一组错误再次出现时停止自动重试。

Planner 是一次独立模型请求，不共享 Generator 的长对话。它接收原始需求、本次 Verification 的全部不同错误、错误位置附近的当前项目代码、简短项目概要及 Generator 报告已完成的子任务；不提供文件编辑工具。源码片段仅在本次请求中读取，不写进长期状态。Planner 返回 JSON：总体目标 `objective`，以及按实施顺序排列的 `subtasks`；每个子任务包含 `id`、问题描述 `problem`、目标 `goal`，可选 `suggested_files` 作为文件提示。扩展仅校验基本格式，把整份计划交回原 Pi 会话，后续每轮系统提示只保留简短的阶段与计划索引。Generator 可在 `godot_verify` 的 `completed_subtasks` 参数中顺带报告已完成项，无须逐项运行 Godot 或调用额外的完成工具。Planner 使用当前 Pi 模型及其推理档位。

验证通过后进入 `review`，对照原始需求；当前工程指纹仍与成功验证时一致且提交了非空需求检查证据，`godot_finish` 才把任务记为 `done`。此处的“通过”仅指 Godot 导入与启动。状态使用 `schemaVersion: 3`；旧会话的无证据 `done` 恢复为 `review`，新版 `done` 保持完成。

验证在系统临时目录复制项目，跳过 `.godot`、`.git`、`.pi` 和 `node_modules`；运行 Godot 导入与无头启动，然后删除副本。报告和完整原始日志保存在顶层 `runs/`。工具结果只显示部分错误，但会标明总数；Planner 接收本次验证识别出的全部不同错误。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；这些仍需试玩或明确的任务检查。`godot_finish` 的需求检查证据由模型提交，无法代替真人试玩。

`/godot-status` 查看当前阶段及最近一次验证。运行需要 `PiAgent/node_modules` 中已有的 `tsx` 以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。
