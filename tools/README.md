# 辅助工具的来源

这个目录放本地游戏检查时使用的参考资料和脚本，不是 Pi 扩展的入口。

| 文件 | 来历与用途 |
| --- | --- |
| [`godot_command_line.md`](godot_command_line.md) | 从 [Godot 官方命令行教程](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)整理的本地参考，供查看 Godot 命令参数。 |
| [`screenshot.ps1`](screenshot.ps1)、[`screenshot.gd`](screenshot.gd) | 本工作区的 Windows 按帧截图助手，原先放在 `LTGDAgentSystem/tools/`，现集中到此目录。PowerShell 脚本启动 Godot，GDScript 在指定帧数后保存画面。 |

截图是可选的人工观察手段，不参与扩展的自动通过判断。脚本从原目录移动后，默认引擎路径仍按旧目录层级计算，因此在当前布局中使用时请明确传入 `-Godot`：

```powershell
.\tools\screenshot.ps1 -Project .\output\game\HSL_LTGD -Out .\frame.png -Frames 30 -Godot .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe
```
