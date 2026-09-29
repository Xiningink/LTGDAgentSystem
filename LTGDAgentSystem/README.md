# Godot-PaT extension

从希望作为工作目录的文件夹启动 Pi，进入后直接用自然语言描述需求。例如从仓库根目录启动：

```powershell
.\LTGDAgentSystem\start.ps1
```

`start.ps1` 和 `start.cmd` 都直接调用 `PiAgent/pi-test.ps1`，只额外加载 `godot-pat/index.ts`，并保留启动时的当前目录。扩展在编辑前调用一次 `godot_set_project`：用户指定了输出路径就使用该路径；未指定时在当前目录下创建 `game/`，把 `project.godot` 等工程文件放在其中。相对输出路径以 Pi 的当前目录为基准。`start.cmd` 保留窗口以显示错误。`PiAgent/.pi/` 中的扩展、skill 和提示词是 Pi 源码开发资源，正常制作游戏时不加载；这些文件仍保留在原处。模型和会话由 Pi 原脚本负责。

扩展提供 `godot_set_project`、`godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors` 和最终的 `godot_finish`。加载扩展不会限制 Pi 的普通读写和命令工具；只有调用 `godot_set_project` 选择项目后才启用游戏任务状态。在同一会话开始另一个游戏时，可用 `godot_set_project` 的 `new_task` 参数重新选择。Pi 的原生读写工具继续负责编辑。主流程是 Generator 制作游戏 → 显式调用 Godot 验证；验证失败时调用 Planner；Generator 根据整份计划修改后统一验证；验证通过再检查原始需求并总结。Agent 结束时不会自动验证；恢复到待规划状态时，再调用 `godot_verify` 会直接继续规划，不重复运行 Godot。同一工程指纹和同一组错误再次出现时停止自动重试。

Planner 是一次独立模型请求，不共享 Generator 的长对话。它接收原始需求、本次 Verification 的全部不同错误、错误位置附近的当前项目代码、简短项目概要及 Generator 报告已完成的子任务；不提供文件编辑工具。源码片段仅在本次请求中读取，不写进长期状态。Planner 返回 JSON：总体目标 `objective`，以及按实施顺序排列的 `subtasks`；每个子任务包含 `id`、问题描述 `problem`、目标 `goal`，可选 `suggested_files` 作为文件提示。扩展仅校验基本格式，把整份计划交回原 Pi 会话，后续每轮系统提示只保留简短的阶段与计划索引。Generator 可在 `godot_verify` 的 `completed_subtasks` 参数中顺带报告已完成项，无须逐项运行 Godot 或调用额外的完成工具。Planner 使用当前 Pi 模型及其推理档位。

验证通过后进入 `review`，对照原始需求；当前工程指纹仍与成功验证时一致且提交了非空需求检查证据，`godot_finish` 才把任务记为 `done`。此处的“通过”仅指 Godot 导入与启动。状态使用 `schemaVersion: 3`；旧会话的无证据 `done` 恢复为 `review`，新版 `done` 保持完成。

验证直接在选定的游戏目录运行 Godot 导入与无头启动；Godot 可能在该目录生成 `.godot` 导入缓存。Verification 结果返回给 Pi 并保存在任务状态中，不创建 `runs/` 报告或日志。`godot_verify` 的简短结果只显示部分错误并标明总数；`godot_get_errors` 可读取本次保存的全部错误，Planner 也接收全部不同错误。若 Godot 非零退出却没有识别出的错误，结果会附带末尾输出用于诊断。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；这些仍需试玩或明确的任务检查。`godot_finish` 的需求检查证据由模型提交，无法代替真人试玩。

`/godot-status` 查看当前阶段及最近一次验证。运行需要 `PiAgent/node_modules` 中已有的 `tsx` 以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。
