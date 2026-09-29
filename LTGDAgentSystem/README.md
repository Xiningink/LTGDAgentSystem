# Godot-PaT extension

先在命令行进入希望作为工作目录的文件夹，再调用 CMD 启动脚本，进入 Pi 后直接用自然语言描述需求。例如从仓库根目录启动：

```cmd
LTGDAgentSystem\start.cmd
```

`start.cmd` 调用系统中已安装的 `pi` 命令，只额外加载 `godot-pat/index.ts`，并保留启动时的当前目录；正常运行不依赖 `PiAgent/`。扩展在编辑前调用一次 `godot_set_project`：用户指定了输出路径就使用该路径；未指定时在当前目录下创建 `game/`，把 `project.godot` 等工程文件放在其中。相对输出路径以 Pi 的当前目录为基准。模型和会话由已安装的 Pi 管理。

扩展提供 `godot_set_project`、`godot_inspect_project`、`godot_inspect_scene`、`godot_verify`、`godot_get_errors`、`godot_propose_work` 和最终的 `godot_finish`。加载扩展不会限制无关 Pi 任务的普通工具；调用 `godot_set_project` 后才启用游戏任务状态。在同一会话收到新的用户请求、开始另一个游戏时，可用 `new_task` 重新选择；重复选择不会改写当前任务的需求。Pi 的原生工具仍负责编辑。选项目时可同时提交从原始需求提炼的 `requirements: [{id,text,doneWhen?}]`；不提交时以完整原始目标作为单条 `R1`。清单固定在当前任务状态中，模型仍须对照原始需求，防止最初提炼时漏项。

## 工作范围授权

Controller 维护可追溯的工作项：原始需求、本次 Godot 验证错误、经复查确认的原始需求缺项。每项记录来源、完成条件、状态、来源证据和 Generator 提交的完成证据；自报完成不等于 Godot 或玩法验证通过。Generator 的观察不能自行变成任务。若发现当前工作集之外可能必须做的事，调用 `godot_propose_work`，引用原始需求或实际 Godot 错误，提交预期、实际、证据和目标。独立的短上下文范围判定只返回 `required`、`optional` 或 `uncertain`；后两者仅记录为建议，不授权继续修改或调查。已关闭的工作项不能因建议重开。Generator 没有主动调用 Planner 的入口。

Generator 只完成当前整组工作；没有未完成的授权项时立即提交 `godot_verify`，不自行开启全面检查或 polish。`review` 中只能使用只读检查与工作流工具，不能借 `bash`、`edit` 或 `write` 修改工程。确认缺项并返回生成阶段后才可继续编辑。此阶段限制针对工作授权，不依赖工具调用次数。

主流程是 Generator 制作游戏 → 提交本轮工作集的逐项报告并显式调用 Godot 验证；验证失败时调用 Planner；Generator 根据整份计划修改后统一验证；验证通过再逐项检查原始需求并总结。当前工作集从状态推导：首次开发取原始 `requirements`，Planner 交接后取整份 `plan`，review 发现遗漏后只取 `pendingRequirements`。`godot_verify` 在实际运行 Godot 前要求 `workset_checks: [{id,status,evidence}]`，每个当前 ID 恰好一条，状态为 `completed` 或 `unresolved`。存在 `unresolved` 时只返回这些未完成项，不运行 Godot、不增加验证次数、不调用 Planner；全部 `completed` 后才运行一次正式验证。Agent 结束时不会自动验证；恢复到待规划状态时，再调用 `godot_verify` 会直接继续规划，不要求报告，也不重复运行 Godot。同一工程指纹和同一组错误再次出现时停止自动重试；代码连续改变两次但同一组错误完全不变时也停止，并报告阻塞原因。错误组变化或减少仍视为进展。

Planner 是独立模型请求，不共享 Generator 的长对话。只有 Controller 记录实际 Godot Verification 失败后才会启动 Planner，处理本次全部不同错误、相关代码、项目概要及已完成子任务。每个子任务必须带 `parentWorkItemId`，引用本次失败产生的工作项，不增加可选目标。Planner 返回 `revise`、原因、目标和有序子任务，或返回 `cannot_resolve_in_project` 及证据。扩展校验父项引用，并用独立范围判定拒绝无关子任务；格式或范围错误至多让 Planner 修正一次。Planner 不编辑文件。整份计划仍由 Generator 完成后统一运行 Godot，不逐项运行。

验证通过后进入 `review`。`godot_finish` 接受每个固定需求 ID 的一条 `checks`：`implemented`、`needs_playtest` 或 `missing`，每项附具体证据；`missing` 还须填写 `expected`、`observed`，由 Controller 范围判定。只有确认必需的缺项返回 `generate`；可选建议不重开任务；无法确认的缺项停止自动工作并报告人工复查需要，不记为完成。没有缺项、且工程指纹与最近一次成功验证一致时才记为 `done`。`needs_playtest` 表示实现存在但仍需人工试玩。`review` 中工程未变化时再次调用 `godot_verify` 会复用成功结果；工程变化后必须用 `reopen_requirement_id` 指明原始需求，并提交其 `workset_checks`。Godot“通过”仅指导入与启动，不能证明玩法。状态使用 `schemaVersion: 5`；旧会话保守迁移工作来源，无法确定来源的旧计划停止自动执行，不会被误判完成。

验证直接在选定的游戏目录运行 Godot 导入与无头启动；Godot 可能在该目录生成 `.godot` 导入缓存。Verification 结果返回给 Pi 并保存在任务状态中，不创建 `runs/` 报告或日志。`godot_verify` 的简短结果只显示部分错误并标明总数；`godot_get_errors` 可读取本次保存的全部错误，Planner 也接收全部不同错误。Godot 正常退出时若仅报告 `ERROR: N resources still in use at exit`，它作为非阻断的退出清理诊断显示，不触发 Planner；其他脚本或导入错误仍会失败，进程非零退出也仍视为失败。若 Godot 非零退出却没有识别出的错误，结果会附带末尾输出用于诊断。工程指纹覆盖选定项目中除缓存和工具目录外的全部普通文件，包括图片、音频等素材。验证前后指纹若不同，本次验证结果作废。`PASS` 只代表导入与启动成功，**不代表玩法、视觉或需求全部通过**；`godot_finish` 的需求检查证据由模型提交，无法代替真人试玩。外部玩法 validator 尚未接入，也不会因 Planner 判断“无需修改”而被自动改判通过。

`/godot-status` 查看当前阶段及最近一次验证。运行需要命令行可调用的 `pi` 和顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。
