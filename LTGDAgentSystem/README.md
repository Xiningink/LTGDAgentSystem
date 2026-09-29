# Godot-PaT extension

在希望作为工作目录的文件夹运行 `LTGDAgentSystem\start.cmd`，然后直接在 Pi 对话中描述游戏。脚本调用已安装的 `pi` 并加载 `godot-pat/index.ts`；正常使用不需要本地 `PiAgent/`。用户指定输出目录时直接使用该目录，否则在 Pi 当前目录创建 `game/`。顶层 `assets/` 和 `Godot_Engine/` 是共享输入，不由 Generator 修改。

系统分为三个角色：

- **Generator** 是 Pi 原生编码 Agent。它直接实现原始需求，不在失败前输出正式计划或细分工单。首版实现写入工程后结束本轮；修复轮只实现 Planner 返回的子任务，然后再次结束本轮。开发时可以针对具体阻碍运行和查看游戏，但不做开放式自检、截图迭代或可选 polish。
- **Executor** 在 Pi 的 `agent_before_settle` 边界自动接管，无需 Generator 记住调用验证工具。它先在选定工程运行 Godot 结构检查、导入和无头启动。通过后，再用独立、短上下文的模型请求审查原始用户需求、提到的任务文件以及当前工程内容。审查只返回 `implemented` 或 `missing`；明确要求缺失或预期玩家流程无法工作才算失败。仅凭主观 polish 建议不得开启修复。运行和需求审查都通过时记为 `done`。
- **Planner** 仅在 Executor 确认 Godot 失败或原始需求缺失后调用。它接收本次错误或缺项、相关工程证据及原始目标，输出针对该失败的最小结构化修复计划；它不能编辑工程，也不能添加可选目标。无法根据证据修复时，流程停止并说明原因。

流程是 `Generator → Executor（Godot → 需求审查）→ done`；任一检查失败则 `Executor → Planner → Generator → Executor`。Executor 和 Planner 不继承 Generator 的整段对话。项目文件是共享事实来源；修复计划作为简短交接返回 Pi，Generator 的 Pi 会话仍然保留自身历史。自动交接解决了 Generator 结束本轮却忘记验证的问题；它不能强制中断尚未结束的 Generator 轮次，生成阶段的及时收手仍取决于明确提示词。

`godot_set_project` 选择工程目录并启动任务。`requirements: [{id,text}]` 仅用于用户明确给出验收项的情况；通常省略，保留完整原始目标作为 `R1`，由 Executor 读取用户提到的任务文件。`godot_inspect_project`、`godot_inspect_scene` 和 `godot_get_errors` 提供简短项目索引、场景结构和最近一次完整 Godot 错误。`godot_verify` 与 `godot_finish` 不再由 Generator 调用。`/godot-status` 可查看阶段和验证结果。

Godot 验证结果只保存在 Pi 会话任务状态中，不生成 `runs/` 报告。验证指纹以 Godot 导入和运行后的工程文件为准，并排除 `.godot` 等缓存目录。相同工程指纹与相同错误重复出现，或修改后连续出现同一错误时，系统停止自动重试。状态使用 `schemaVersion: 7`；旧会话的需求、计划和验证记录会在恢复时转换。Godot PASS 仅代表导入与启动通过，需求是否满足由随后独立审查决定。

## 按帧截图（Windows）

Linux 任务说明中的 `/workspace/tools/screenshot.sh` 不在这个工作区。需要查看游戏画面时，可在仓库根目录运行：

```powershell
.\LTGDAgentSystem\tools\screenshot.ps1 -Project .\game -Out .\frame.png -Frames 60
.\LTGDAgentSystem\tools\screenshot.ps1 -Project .\game -Out .\battle.png -Frames 120 -Scenario battle
```

可用 `-Scene 'res://scenes/Battle.tscn'` 指定启动场景，或用 `-GameArgs @('--difficulty', 'hard')` 向游戏传递其他参数。助手调用本地 Godot 的 Movie Maker 导出 PNG 帧，将最后一帧复制到 `-Out`，并清理临时帧。它会启动有画面的 Godot 窗口，不使用 `--headless`；场景参数会留在 `OS.get_cmdline_user_args()`。游戏须自行实现 `--scenario` 对应的状态跳转。
