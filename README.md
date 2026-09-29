# LTGD Agent System

这里用 Pi 作为游戏开发入口。在命令行进入希望作为工作目录的文件夹，再运行 LTGD 的 CMD 脚本并用自然语言描述需求。

```cmd
LTGDAgentSystem\start.cmd
```

脚本调用已安装的 `pi` 命令并加载 PaT 扩展，不依赖本地 `PiAgent/`。用户指定输出目录时使用该目录；未指定时在当前目录创建 `game/`。模型、登录信息与会话仍由 Pi 管理。扩展源码与流程见 [LTGDAgentSystem](LTGDAgentSystem/README.md)。

扩展提供项目、场景和 Godot 验证工具，Pi 的原生工具负责编辑。Generator 直接制作游戏，在完成当前功能后调用正式 Godot 验证；失败时由短上下文 Planner 生成修复计划，修改完后统一复验。正式验证通过后只读复查原始需求，具体缺项才重新进入生成阶段。验证结果保存在 Pi 任务状态中。Godot 通过只表示可以导入和启动，玩法仍须对照需求检查及人工试玩。

顶层 `assets/` 是只读公共素材库，`Godot_Engine/` 是本地 Godot 4.6.2。历史 Python 实现仍在相邻的 `../GameEva/` 仓库，仅作为迁移参照，不是新入口。
