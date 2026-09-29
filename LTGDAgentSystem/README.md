# LTGD Godot PaT extension

在希望作为 Pi 工作目录的文件夹中运行 `LTGDAgentSystem\start.cmd`，然后用自然语言描述游戏。脚本调用已安装的 `pi` 并加载 `godot-pat/index.ts`；正常使用不依赖本地 `PiAgent/`。用户指定输出目录时使用该目录，否则在 Pi 当前目录创建 `game/`。生成过程不修改公共 `assets/` 或 `Godot_Engine/`。

## 流程

1. `godot_set_project` 读取用户任务及任务文件，用一次独立模型请求提取游戏交付需求。同一功能的细节合并为一项；运行环境、工具调用和文件读取等流程信息不作为游戏需求。Controller 校验每项 `sourceEvidence` 是否逐字来自原文；进入生成阶段后，当前任务不能替换需求清单。用户消息中写出的 `.md`、`.txt`、`.toml` 路径会被读取，当前目录和所选项目目录中的 `instruction.md`、`task.toml` 也会自动读取。其他文件可通过 `specification_files` 指定。Generator 提供的 `requirements` 仅作为提取提示。
2. Generator 使用 Pi 原生工具完成当前整组需求，并通过 `godot_verify` 一次提交每项的 `completed`/`unresolved` 报告。有未完成项时继续生成，不运行 Godot。
3. Verifier 检查项目结构、Godot 导入及无头启动。真正失败时，Controller 调用一次短上下文 Planner。Planner 只接收本次错误、相关代码和简短项目概要，返回整份修复计划；Generator 完成计划后再统一验证。相同错误反复出现会停止自动重试。
4. Godot PASS 后进入 `review`，逐项检查原始需求。`godot_finish` 发现 `missing` 时，直接把这些原始需求送回 Generator；无缺项时记录完成，并说明仍需人工试玩的内容。

`review` 阶段的工具门禁禁止 `write`、`edit`、`bash` 等修改操作，只允许读取和 `godot_finish`。因此 PASS 后不会自动开启 polish。Godot PASS 仅证明项目能够导入和启动，不证明玩法、音效或画面满足需求。完成前会核对当前工程指纹是否与 PASS 时一致；验证期间工程发生变化则本次结果作废。

`godot_inspect_project` 提供简短项目索引，`godot_inspect_scene` 提供场景结构，`godot_get_errors` 返回保存在 Pi 会话中的全部验证错误。不会创建单独的验证报告文件。`/godot-status` 显示当前阶段和最近一次验证。

运行需要命令行可调用的 `pi`，以及顶层 `Godot_Engine/Godot_v4.6.2-stable_win64_console.exe`。需求提取依赖模型判断，逐字来源校验不能保证语义上零遗漏；此流程不代替真人试玩。
