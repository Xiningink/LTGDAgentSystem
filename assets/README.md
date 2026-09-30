# 获取共享素材

这个目录用于本地存放游戏生成任务可读取的共享素材库。仓库只跟踪本说明，不上传素材文件。LTGD 会要求 Generator 不修改本目录；生成的游戏工程应把实际使用的资源复制到自己的输出目录，并按相应许可保留来源信息。

本地素材按来源分成两个目录：

| 本地路径 | 获取方式 |
| --- | --- |
| `assets/library/` | 从 [Kenney 素材目录](https://kenney.nl/assets)下载任务需要的 2D、UI、音频、字体或纹理包，解压后按类别放入本目录。例如 `assets/library/2D/`、`assets/library/Audio/`、`assets/library/Textures/`。 |
| `assets/library-oga/` | 从 [OpenGameArt 素材搜索](https://opengameart.org/art-search)下载任务需要的单个素材包，建议每个素材包独立建目录，例如 `assets/library-oga/<素材包名>/`，并保留该包的 `LICENSE.txt`、署名说明和原始页面地址。 |

本地库是按任务逐步收集的素材包集合，没有一个与整个 `assets/` 完全对应的单一下载包。只想运行 LTGD 插件时，这个目录可以只有 README；如果任务说明要求共享素材，则按需要下载对应包。现有任务说明中的路径与素材类别见 [`tasks/README.md`](../tasks/README.md)。

Kenney 和 OpenGameArt 上的素材许可需按**具体素材包**核对。尤其是 OpenGameArt，不同投稿可能使用不同许可及署名要求；把资源加入生成游戏前，应查看下载页和包内许可文件。
