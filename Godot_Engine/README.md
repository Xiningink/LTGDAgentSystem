# 获取 Godot 引擎

这个目录在本地放 Godot 引擎；仓库只跟踪本说明，不上传可执行文件。

1. 打开 [Godot 4.6.2 stable 官方下载页](https://godotengine.org/download/archive/4.6.2-stable/)。
2. 下载 **Windows Standard x86_64** 版本并解压。当前插件使用标准版，不使用 .NET 版。
3. 将解压得到的两个程序直接放在本目录，保持以下文件名：

   ```text
   Godot_Engine/
   ├── Godot_v4.6.2-stable_win64.exe
   └── Godot_v4.6.2-stable_win64_console.exe
   ```

LTGD 扩展在 [`godot-pat/index.ts`](../LTGDAgentSystem/godot-pat/index.ts) 中按上述路径调用 `Godot_v4.6.2-stable_win64_console.exe` 做导入和启动检查。若换用其他 Godot 版本或文件名，需要同步调整扩展中的路径；仅把新版程序放进目录不会自动切换。

在仓库根目录可用 PowerShell 检查安装：

```powershell
& .\Godot_Engine\Godot_v4.6.2-stable_win64_console.exe --version
```
