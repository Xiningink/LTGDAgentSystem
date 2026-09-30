# 报告工具的来源

这个目录保存 LTGD 开发过程中使用的 Pi 用量导出工具。现有的 [`pi-token-usage/export_pi_usage.py`](pi-token-usage/export_pi_usage.py) 读取本机 Pi 会话 JSONL，汇总模型调用的 Token、费用和会话信息，并可导出逐次调用表与会话日志。脚本默认把结果写到自身所在目录下，以会话 ID 建立子目录；也可以用 `--out` 指向其他目录。

本次整理中留下的实验导出结果放在 [`../output/token_usage/`](../output/README.md)，按游戏任务和运行方式分组。它们是本地 Pi 会话的记录，不是在线服务产生的统计，也不是 GameCraft-Bench 官方评分。命令和字段含义详见 [Pi 用量导出说明](pi-token-usage/README.md)。
