# Godot-PaT extension

在希望作为工作目录的文件夹运行 `LTGDAgentSystem\start.cmd`，然后直接在新的 Pi 会话中描述游戏。脚本调用已安装的 `pi` 并加载 `godot-pat/index.ts`；正常使用不需要本地 `PiAgent/`。首条请求自动启动 LTGD 任务。用户指定输出目录时 Generator 直接在该目录创建 Godot 工程，否则使用 Pi 当前目录下的 `game/`。顶层 `assets/` 和 `Godot_Engine/` 是共享输入，不由 Generator 修改。

系统分为三个角色：

- **Generator** 是 Pi 原生编码 Agent。它直接实现原始需求，不在失败前输出正式计划或细分工单。首版实现写入工程后结束本轮；修复轮只实现 Planner 返回的子任务，然后再次结束本轮。开发时可以针对具体阻碍运行和查看游戏，但不做开放式自检、截图迭代或可选 polish。
- **Executor** 在 Pi 的 `agent_before_settle` 边界自动接管，无需 Generator 记住调用验证工具。它定位唯一的 `project.godot`，再运行 Godot 结构检查、导入和无头启动。通过后，用独立、短上下文的模型请求审查原始用户需求、实际输出路径、任务文件和当前工程内容。审查只返回 `implemented` 或 `missing`；明确要求缺失或预期玩家流程无法工作才算失败。仅凭主观 polish 建议不得开启修复。运行和需求审查都通过时记为 `done`。
- **Planner** 仅在 Executor 确认 Godot 失败或原始需求缺失后调用。它接收本次错误或缺项、相关工程证据及原始目标，输出针对该失败的最小结构化修复计划；它不能编辑工程，也不能添加可选目标。无法根据证据修复时，流程停止并说明原因。

流程是 `Generator → Executor（Godot → 需求审查）→ done`；任一检查失败则 `Executor → Planner → Generator → Executor`。Executor 和 Planner 不继承 Generator 的整段对话。项目文件是共享事实来源；修复计划作为简短交接返回 Pi，Generator 的 Pi 会话仍然保留自身历史。自动交接解决了 Generator 结束本轮却忘记验证的问题；它不能强制中断尚未结束的 Generator 轮次，生成阶段的及时收手仍取决于明确提示词。

无需调用项目设置工具。Executor 会在 Pi 当前目录内寻找唯一的 `project.godot`；用户明确写出目录外的输出路径时，也会检查该路径。找不到或找到多个工程时会报告原因，不会猜测。`godot_inspect_project` 和 `godot_inspect_scene` 提供简短项目索引与场景结构。`/godot-status` 可查看阶段和验证结果。完成一个游戏后，可用新的 Pi 会话开始下一个游戏。

Godot 验证结果只保存在 Pi 会话任务状态中，不生成 `runs/` 报告。验证指纹以 Godot 导入和运行后的工程文件为准，并排除 `.godot` 等缓存目录。如果 Planner 要求修复后工程文件仍未变化，系统停止重复检查。Godot PASS 仅代表导入与启动通过，需求是否满足由随后独立审查决定。

## 按帧截图（Windows）

Linux 任务说明中的 `/workspace/tools/screenshot.sh` 不在这个工作区。需要查看游戏画面时，可在仓库根目录运行：

```powershell
.\LTGDAgentSystem\tools\screenshot.ps1 -Out .\frame.png -Frames 30
.\LTGDAgentSystem\tools\screenshot.ps1 -Out .\battle.png -Frames 120 -Scenario battle
```

助手默认使用当前目录中的 Godot 工程；若当前目录不是工程，则使用其下的 `game/`。用户把游戏生成到其他目录时，可先进入该目录，或传 `-Project` 指定。可用 `-Scene 'res://scenes/Battle.tscn'` 指定启动场景，或用 `-GameArgs @('--difficulty', 'hard')` 向游戏传递其他参数。助手参考 Linux 版流程：通过 Windows 图形驱动和 OpenGL3 启动 Godot，在 1280×720 窗口中运行 `screenshot.gd`，等待指定帧数后读取 viewport 并保存 PNG。不能使用 `--headless`，因为它没有可截图的 viewport 纹理。参数经 `--` 传给脚本，游戏也可从 `OS.get_cmdline_user_args()` 读取 `--scenario`；游戏须自行实现对应的状态跳转。截图先写入临时目录，成功后复制到 `-Out`。
