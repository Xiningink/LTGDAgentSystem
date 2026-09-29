# LTGD Agent System

这里用 Pi 作为游戏开发入口。在命令行进入希望作为工作目录的文件夹，再运行 LTGD 的 CMD 脚本并用自然语言描述需求。

```cmd
LTGDAgentSystem\start.cmd
```

脚本调用已安装的 `pi` 命令并加载 PaT 扩展，不依赖本地 `PiAgent/`。用户指定输出目录时使用该目录；未指定时在当前目录创建 `game/`。模型、登录信息与会话仍由 Pi 管理。扩展源码与流程见 [LTGDAgentSystem](LTGDAgentSystem/README.md)。

扩展让 Pi 原生 Generator 直接制作游戏。Generator 结束本轮后，Executor 自动运行 Godot 导入与启动验证，再独立审查原始需求；任一检查确认失败才调用短上下文 Planner，Generator 按修复计划修改后再次交给 Executor。两项检查均通过后，任务标记为完成。验证结果保存在 Pi 任务状态中。

顶层 `assets/` 是只读公共素材库，`Godot_Engine/` 是本地 Godot 4.6.2。历史 Python 实现仍在相邻的 `../GameEva/` 仓库，仅作为迁移参照，不是新入口。

在 Windows 上需要查看游戏实际画面时，可用 [按帧截图助手](LTGDAgentSystem/README.md#按帧截图windows)。
