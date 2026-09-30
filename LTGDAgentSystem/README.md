# LTGD 工作流程与角色职责

LTGD（Low-Token Game Development）的核心顺序是**先生成可检查的 Godot 工程，再根据实际失败决定是否规划修复**。用户始终在 Pi 对话中用自然语言提出游戏需求；LTGD 扩展负责交接、验证和状态转换。一次任务只有三个 Agent 角色：Generator、Executor 和 Planner。Executor 内部的需求审查虽会单独调用模型，但它属于 Executor 的检查阶段，不是第四个 Agent。

## 入口与输出

在希望作为工作目录的文件夹运行 `LTGDAgentSystem\start.cmd`，然后在新的 Pi 会话中描述游戏。CMD 脚本调用已安装的 `pi` 并加载 `godot-pat/index.ts`，正常使用不需要本地 `PiAgent/`。首条请求自动成为本次任务的原始目标。

用户指定输出目录时，游戏写入该目录；否则写入 Pi 当前工作目录下的 `game/`。顶层 `assets/` 和 `Godot_Engine/` 是共享输入，不属于生成工程，Generator 不修改它们。Pi 管理对话、模型和普通编码工具；LTGD 扩展管理任务状态，并把验证结果保存在 Pi 会话中。

## 三个角色各负责什么

| 角色 | 何时工作 | 职责与交付物 | 职责边界 |
| --- | --- | --- | --- |
| **Generator（生成者）** | 用户提出需求后；或收到 Planner 的修复步骤后 | 使用 Pi 的编码工具，在目标目录创建或修改 `project.godot`、场景、脚本和所需资源。首轮直接完成原始需求中的玩家流程；修复轮只处理交接的具体失败。每轮结束时交出实际工程路径。 | 不在首轮前请求正式规划；不自行宣布任务通过；完成一轮后停止开放式自检和可选润色，交给 Executor 检查。遇到具体编码阻碍时可以做必要的本地运行或查看。 |
| **Executor（执行与验收者）** | Generator 正常结束一轮时，由扩展自动触发 | 绑定 Generator 交出的工程目录，运行 Godot 结构检查、导入和无头启动；Godot 通过后，再用独立模型请求核对原始需求与当前工程。输出通过、具体失败或停止原因，并决定下一阶段。 | 不编辑工程，也不把 Godot 启动成功当作需求全部满足；只根据检查证据触发修复。 |
| **Planner（修复规划者）** | Executor 确认 Godot 失败，或确认原始需求有具体缺项时 | 读取原始目标、本次错误或缺项及相关工程证据，给出有顺序的最小修复步骤；证据不足以支持工程修改时说明无法在工程内解决。 | 不参与无失败的首轮生成，不编辑文件，不扩展原始需求或添加可选目标。 |

## 从需求到完成的完整流程

1. **创建任务。** 用户在 Pi 中描述目标。扩展记录原始请求，状态进入 `generate`。Generator 直接制作第一版工程，不先启动 Planner。
2. **Generator 交接工程。** 首版具备所要求的主要玩家流程后，Generator 结束本轮，并在最后一行写出 `<ltgd-project-path>实际工程目录</ltgd-project-path>`。修复轮也用同一格式交接；首次绑定后的路径会保存在会话状态中。Executor 只检查交接的目录，不扫描其他工程或从用户文字猜测目录。缺少路径，或目录内没有 `project.godot`，流程停止并报告原因。
3. **Executor 检查 Godot。** 它先确认工程有 `.tscn` 场景且配置了主场景，再运行 Godot 编辑器导入，最后无头启动 60 帧。导入最多等待 60 秒，启动最多等待 25 秒。检查失败时保留阶段、错误和能定位到的文件行号；引擎缺失、超时或验证中断等基础设施问题会停止流程。Godot 通过只表示工程可导入、可启动。
4. **Executor 审查原始需求。** 仅在 Godot 通过后，独立模型请求读取原始要求、相关任务文件、实际输出目录以及当前工程文件，判断为 `implemented` 或 `missing`。明确要求的功能缺失、路径错误，或源码证据表明预期玩家流程无法工作，才会进入修复；纯主观润色和未证实的猜测不会触发修复。此审查会消耗模型 Token，也不能代替人工游玩或视觉验收。
5. **按失败情况分流。** Godot 与需求审查都通过，状态变为 `done`。Godot 有可修复错误，或需求审查发现具体缺项，状态变为 `plan`，Planner 根据这一次的证据返回结构化修复步骤。若 Planner 判断工程修改无法解决问题，状态变为 `stopped` 并说明依据。
6. **定向修复并复查。** Planner 的步骤交还给 Generator，状态重新进入 `generate`。Generator 只修复这些问题，再结束本轮；Executor 对改动后的工程重新执行检查。这个循环可重复，直到通过或遇到停止条件。如果修复轮之后工程文件没有变化，系统会停止重复验证。

简写为：`用户需求 → Generator → Executor〔Godot 检查 → 需求审查〕→ done`；确认失败时走 `Executor → Planner → Generator → Executor`。

例如，用户要求一个可以扫描信号的游戏。若首版没有主场景，Executor 会在 Godot 结构检查时失败，Planner 只安排补齐相关场景。补齐后若工程可以启动，但需求审查发现扫描交互并未实现，Planner 再安排这一项；扫描流程实现且两项检查通过后，任务才进入 `done`。

## 交接信息与停止条件

工程文件是各角色共同依据的事实来源。Executor 和 Planner 使用独立的短上下文请求，不继承 Generator 的整段对话；Generator 的 Pi 会话保留自己的历史。Godot 检查后的工程文件指纹会与需求审查对应，避免用旧检查结果验收已改变的工程。`.godot` 等缓存目录不计入工程指纹。

路径无效、验证基础设施失败、审查输入过大、模型请求失败、修复后文件未变化，或 Planner 给出有证据的无法修复结论时，任务进入 `stopped` 并报告原因。自动交接发生在 Generator **正常结束本轮**的边界，扩展不会强行打断尚在工作的 Generator。`/godot-status` 可查看当前阶段和最近一次 Godot 验证；路径绑定后，`godot_inspect_project` 和 `godot_inspect_scene` 可提供简短工程索引与场景结构。完成一个游戏后，用新的 Pi 会话开始下一个任务。

## 按帧截图（Windows）

Linux 任务说明中的 `/workspace/tools/screenshot.sh` 不在这个工作区。需要查看游戏画面时，可在仓库根目录运行：

```powershell
.\LTGDAgentSystem\tools\screenshot.ps1 -Out .\frame.png -Frames 30
.\LTGDAgentSystem\tools\screenshot.ps1 -Out .\battle.png -Frames 120 -Scenario battle
```

助手默认使用当前目录中的 Godot 工程；若当前目录不是工程，则使用其下的 `game/`。用户把游戏生成到其他目录时，可先进入该目录，或传 `-Project` 指定。可用 `-Scene 'res://scenes/Battle.tscn'` 指定启动场景，或用 `-GameArgs @('--difficulty', 'hard')` 向游戏传递其他参数。助手参考 Linux 版流程：通过 Windows 图形驱动和 OpenGL3 启动 Godot，在 1280×720 窗口中运行 `screenshot.gd`，等待指定帧数后读取 viewport 并保存 PNG。不能使用 `--headless`，因为它没有可截图的 viewport 纹理。参数经 `--` 传给脚本，游戏也可从 `OS.get_cmdline_user_args()` 读取 `--scenario`；游戏须自行实现对应的状态跳转。截图先写入临时目录，成功后复制到 `-Out`。
