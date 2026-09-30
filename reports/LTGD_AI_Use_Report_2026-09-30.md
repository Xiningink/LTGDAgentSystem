# LTGD 项目 AI 辅助使用报告

编码、报告写作与框架图制作记录 | 2026 年 9 月 30 日

## 1 使用范围

本项目把 Pi 对话作为游戏需求入口。Pi 的原生编码 Agent 担任 Generator，负责写 Godot 工程；LTGD 扩展在它结束一轮后自动调用 Godot，并用独立模型请求核查需求。只有检查发现明确失败时，Planner 才给出修复步骤。这是项目代码中实际存在的 AI 分工。编写本次报告时，我还使用 Codex 阅读源码、旧报告和历史记录，起草英文报告、改写中文说明，并用 Python 绘制框架图和排版 DOCX。绘图使用确定的形状与箭头，没有使用图像生成模型。

## 2 AI 如何辅助编码

Generator 从用户的自然语言直接编写场景和脚本，最后交出真实工程路径。Executor 在 `agent_before_settle` 事件中读取该路径，运行结构、导入和无头启动检查。Godot 通过后，另一次短上下文模型调用对照原始需求、任务文件和项目源码，返回 `implemented` 或 `missing`。若检查确认失败，Planner 根据错误和相邻源码输出 JSON 修复步骤，再交给 Generator 修改。源码见 `LTGDAgentSystem/godot-pat/index.ts`、`godot.ts`、`executor.ts` 和 `planner.ts`。

### 2.1 三个角色怎样接力

Generator 是 Pi 原生编码 Agent。首次收到需求时，它直接在用户指定目录（未指定时为 Pi 当前目录的 `game/`）制作工程，不先开一轮正式规划；结束时用 `<ltgd-project-path>` 交出实际路径。修复轮收到的只是已确认的问题和 Planner 的短步骤，提示词要求它只改这些问题。这种安排把长对话和文件编辑留在 Generator 一侧。

Executor 是自动检查环节。Generator 结束本轮后，扩展的 `agent_before_settle` 钩子绑定其交接路径，要求该目录有 `project.godot`，再检查主场景、Godot 导入和无头启动。通过后，它用独立模型请求对照原始需求、任务文件和工程源码；工程指纹用于防止审查期间文件变化后仍沿用旧的 Godot PASS。只有引擎检查通过且需求审查返回 `implemented`，状态才到 `done`。引擎失败或审查发现具体缺项时，Executor 把证据送往 Planner。

Planner 不写游戏代码。Godot 报错时，它收到最新错误及相关源码片段；需求审查报缺项时，它收到缺项证据和工程概览。它只返回针对该问题的 JSON 修复步骤，或说明无法根据工程证据修复。随后 Generator 按步骤修改，Executor 再验。这样，规划发生在已观察到失败之后，且 Planner 无需读完 Generator 的整段对话。

测试中的一条交接路径很直观：主场景缺失使 Godot 检查失败；Planner 要求补场景。补完后 Godot 通过，但模拟的需求审查指出“信号扫描交互缺失”；Planner 再给出修复步骤。Generator 写入 `Game.gd` 后，下一轮检查与模拟审查通过，任务进入 `done`。这条测试证明状态能按预期流转，不能代替对扫描玩法的真人试玩。

这次没有把 AI 返回的“完成”当作测试结论。我运行了仓库的 12 项测试，结果为 12 通过、0 失败；其中包含真实 Godot 导入与启动。另将 `output/game/` 的六份历史目录复制到临时目录后重查：五份通过导入和无头启动，`MAG_direct` 缺少 `project.godot`。这个结果只说明技术启动情况，不说明游戏玩法已经符合任务书。对历史用量，我保留了原始会话导出的数值，却没有据此写“LTGD 节省了多少 Token”的结论；这些会话早于当前实现，每个条件也只有一次记录。

## 3 AI 如何辅助写作与作图

英文报告的初稿依据 README、扩展源码、测试、历史 DOCX 和用量导出生成。我逐段核对“谁触发下一步”“检查的是哪个目录”“通过的含义”以及每个数字的来源。旧 DOCX 写的是手动 `godot_verify`、先局部修复再规划、`godot_finish` 完成；当前代码已改成结束轮次后自动检查、首次确认失败即调用 Planner、独立需求审查后才完成。英文报告因此重写了方法、图注和局限性，而不是沿用旧稿的流程。

框架图用 Python 绘制，先列节点，再为每条箭头写触发条件。图 1 区分 Pi、LTGD 扩展、Godot 和两个模型审查步骤；图 2 单独表示失败与返回路径。英文报告的图注限定了图的证据范围：`done` 需要 Godot PASS 和需求审查通过，但图不能证明游戏可玩。

## 4 发现的问题与修改前后对比

| 检查对象 | 修改前 | 修改后 | 修改原因 |
| --- | --- | --- | --- |
| 英文方法叙述 | 旧报告：“On the first technical failure, the controller enters repair ... A second failed verification moves to plan.” | 新报告：“Any confirmed Godot failure or concrete missing requirement moves the task to `plan`.” | `controller.ts` 的 `recordVerification` 在首次失败后即设为 `plan`；旧句已与代码不符。 |
| 完成条件 | 旧图使用 “Verified → Finish gate / godot_finish to done”。 | 新图使用 “Godot PASS → Requirement review → done”，`missing` 返回 Planner。 | 当前实现没有 `godot_finish` 工具；需求审查是独立模型请求。 |
| 初稿中的套话 | “本系统并不是盲目生成游戏，而是通过多角色闭环确保质量。” | “Generator 写入工程后，Executor 自动导入并启动 Godot；需求审查另行检查原始要求。两项通过才记为 `done`。” | 初稿用否定式解释和“确保质量”掩盖了检查边界。修订句交代动作与完成条件。 |
| 结果表述 | “LTGD 显著降低 Token 消耗并提高游戏质量。” | “三组历史 LTGD 会话的记录总量较低；当前资料不能证明这种差异由扩展造成，也没有共同的玩法评分。” | 每组只有一次旧版本会话，缺少相同评价标准，不能做因果或质量判断。 |

下图把旧报告 Figure 2 的关系按原意重绘。它显示“首次失败先局部修复”和“godot_finish 完成”，适合旧实现，却会误导读者理解当前代码。

![旧报告流程关系重绘](figures/ltgd_legacy_flow_2026-09-30.png)

英文技术报告使用的新版图把两个失败入口都接到 Planner，并把 Godot 检查和需求审查分开。箭头上的 `FAIL`、`MISSING`、`PASS` 是实际分支条件，不是装饰。

![当前实现的失败与返回路径](figures/ltgd_control_flow_2026-09-30.png)

## 5 检查和修正方式

我用源码核对流程，尤其检查 `recordVerification`、`finishTask` 和 `agent_before_settle` 的转移；用测试结果确认这些分支可执行；用隔离副本重跑 Godot，避免把历史截图或会话总结误当作当前验证。复核用量目录时还发现原英文表漏掉了 `output/token_usage/PIB_LTGD/usage.json`。补入后，Ivory Beats 的 Direct 与 LTGD 记录分别为 8,268,231 和 5,121,436 Total Tokens。写作后又检查夸大词、空泛的“闭环”说法和“不是……而是……”式句子，把它们改为有文件或测试支撑的动作。作图后逐条追踪箭头：Godot 失败不能直达 `done`，需求缺失不能绕过 Planner，Planner 不能直接改工程。最后渲染两份 DOCX，检查分页、表格、图中字形和箭头是否清楚。

## 6 结论与仍需人工判断的部分

LTGD 已实现一条有明确交接条件的工作流：Generator 负责写与修，Executor 自动核查工程和原始需求，Planner 只对确认的失败提出修复步骤。12 项测试通过，说明这些分支及启动入口可执行；五份历史工程快照通过本次 Godot 启动检查。三组历史会话中，LTGD 的 Total Tokens 比对应 Direct 记录分别低 50.1%（Horror Signal Lost）、43.8%（Puzzle Magnet Lab）和 38.1%（Ivory Beats）；估算费用分别低 41.6%、31.0% 和 26.0%。这是三个单次任务的观察结果，与“减少无依据的规划和反复自检”的设计意图一致，但不能证明差异由当前版本造成。

独立需求审查读取项目文字，无法代替玩家操作和视觉检查。Godot 无头启动也不会覆盖完整关卡流程。因此目前可以得出“自动验证与失败后定向修复机制已实现、历史记录呈现较低用量”的结论，不能得出“游戏质量提高”或“当前版本稳定节省 Token”的结论。后两项需要固定任务输入、重复运行，并用同一套玩法评价标准比较。
