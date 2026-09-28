# LTGD Agent System

这里用 Pi 作为游戏开发入口。先进入 `games/` 下的 Godot 项目目录，再运行 LTGD 启动脚本；它会直接调用 Pi 原来的启动脚本并加载扩展。进入 Pi 后用自然语言描述需求。

```powershell
cd games\system
..\..\LTGDAgentSystem\start.ps1
```

也可以双击 `LTGDAgentSystem\start.cmd`，它会直接调用 Pi 原脚本，从 `games/system` 启动并保留窗口。两个入口只额外加载 PaT 扩展；`PiAgent/.pi/` 中的开发者扩展、skill 和提示词仍保留在原处，正常制作游戏时不加载。当前目录就是 Pi 编辑和验证的游戏项目；模型、登录信息与会话继续由 Pi 管理。扩展源码与说明见 [LTGDAgentSystem](LTGDAgentSystem/README.md)。

扩展提供精简的项目和场景检查工具，Pi 的原生工具负责编辑。它在隔离副本上检查项目结构、Godot 导入与启动；失败后先局部修复，再触发结构化规划。基础设施故障不触发规划。验证证据和 Token 用量保存在 `runs/`。相同文件与错误再次出现会停止自动重试。检查通过只表示可导入和启动，仍需真人试玩；试玩问题直接在原会话用自然语言反馈。

顶层 `assets/` 是只读公共素材库，`Godot_Engine/` 是本地 Godot 4.6.2。历史 Python 实现仍在相邻的 `../GameEva/` 仓库，仅作为迁移参照，不是新入口。
