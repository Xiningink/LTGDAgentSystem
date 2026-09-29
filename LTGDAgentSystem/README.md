# Godot-PaT extension

先在命令行进入希望作为工作目录的文件夹，再调用 CMD 启动脚本，进入 Pi 后直接用自然语言描述需求。例如从仓库根目录启动：

```cmd
LTGDAgentSystem\start.cmd
```

`start.cmd` 调用系统中已安装的 `pi` 命令，只额外加载 `godot-pat/index.ts`，并保留启动时的当前目录；正常运行不依赖 `PiAgent/`。扩展在编辑前调用一次 `godot_set_project`：用户指定了输出路径就使用该路径；未指定时在当前目录下创建 `game/`，把 `project.godot` 等工程文件放在其中。相对输出路径以 Pi 的当前目录为基准。模型和会话由已安装的 Pi 管理。

扩展提供 `godot_set_project`、`godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors` 和最终的 `godot_finish`。加载扩展不会限制 Pi 的普通读写和命令工具；只有调用 `godot_set_project` 选择项目后才启用游戏任务状态。在同一会话收到新的用户请求、开始另一个游戏时，可用 `godot_set_project` 的 `new_task` 参数重新选择；重复选择不会改写当前任务的需求。Pi 的原生读写工具继续负责编辑。选项目时可同时提交从原始需求提炼的 `requirements: [{id,text}]`：按完整玩法、界面或体验分组，保留具体要求，不把每句话、操作步骤或笼统的“更精致”拆成独立项；不提交时以完整原始目标作为单条 `R1`。清单固定在当前任务状态中，完成复查使用这些 ID。模型仍须对照原始需求，防止最初提炼时漏项。

主流程是 Generator 直接制作游戏 → 完成当前功能后显式调用 Godot 验证；验证失败时调用 Planner；Generator 根据整份计划修改后统一复验；验证通过后只读复查原始需求并总结。当前工作集从状态推导：首次开发取原始 `requirements`，Planner 交接后取整份 `plan`，review 发现遗漏后只取 `pendingRequirements`。生成阶段可以运行游戏和检查实现，但不应在功能已完成后开启无明确目标的 polish 循环。`godot_verify` 不要求 Generator 自报逐项完成证据。Agent 结束时不会自动验证；恢复到待规划状态时，再调用 `godot_verify` 会直接继续规划，不重复运行 Godot。同一工程指纹和同一组错误再次出现时停止自动重试；代码连续改变两次但同一组错误完全不变时也停止，并报告阻塞原因。错误组变化或减少仍视为进展。

Planner 是一次独立模型请求，不共享 Generator 的长对话。它接收原始需求、本次 Verification 的全部不同错误、错误位置附近的当前项目代码及简短项目概要；不提供文件编辑工具。每个 Planner 子任务应针对本次正式 Verification 观察到的错误，不增加可选目标。源码片段仅在本次请求中读取，不写进长期状态。Planner 返回 JSON 决策：`revise` 带 `reason`、总体目标 `objective` 和有序 `subtasks`；每个子任务包含 `id`、`problem`、`goal`，可选 `suggested_files` 仅作文件提示。若当前证据无法支持修改工程，返回 `cannot_resolve_in_project`、原因和验证证据；扩展停止自动修改并报告阻塞，而不是把失败当作通过。格式错误时至多重试一次。Planner 使用当前 Pi 模型及其推理档位。

验证通过后进入 `review`，Controller 只允许读取、检查以及 `godot_finish`，阻止编辑和 shell 命令。`godot_finish` 接受每个固定需求 ID 的一条 `checks`：`implemented` 或 `missing`，每项附具体证据。存在 `missing` 时返回 `generate`，只继续实现这些原始缺项；修复后重新运行正式 Godot 验证。工程未变化时不会为了这些缺项重复运行 Godot。没有缺项，且工程指纹仍与最近一次成功验证一致时才记为 `done`。此处的 Godot“通过”仅指导入与启动，需求审查负责判断原始要求。状态使用 `schemaVersion: 6`；旧会话缺少需求清单时以原始目标作为 `R1`，无版本且无完成证据的旧 `done` 恢复为 `review`，已完成的新版任务保持完成。

验证直接在选定的游戏目录运行 Godot 导入与无头启动；Godot 可能在该目录生成 `.godot` 导入缓存。Verification 结果返回给 Pi 并保存在任务状态中，不创建 `runs/` 报告或日志。`godot_verify` 的简短结果只显示部分错误并标明总数；`godot_get_errors` 可读取本次保存的全部错误，Planner 也接收全部不同错误。Godot 正常退出时若仅报告 `ERROR: N resources still in use at exit`，它作为非阻断的退出清理诊断显示，不触发 Planner；其他脚本或导入错误仍会失败，进程非零退出也仍视为失败。若 Godot 非零退出却没有识别出的错误，结果会附带末尾输出用于诊断。工程指纹覆盖选定项目中除缓存和工具目录外的全部普通文件，包括图片、音频等素材。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；`godot_finish` 根据项目证据复查原始需求。外部玩法 validator 尚未接入，也不会因 Planner 判断“无需修改”而被自动改判通过。

`/godot-status` 查看当前阶段及最近一次验证。运行需要命令行可调用的 `pi` 和顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。
