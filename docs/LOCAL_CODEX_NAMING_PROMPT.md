# 本地 Codex 同步提示词

请在本地 RTTGame 仓库同步已确认的品牌命名变更。

正式名称：GreyLine Taskforce / 灰线战术群。
内部代号：GREYLINE / 灰线。
远程主仓库：https://github.com/Halfaustus/RTTGame.git，仓库地址未改名。

先检查 git status、当前分支、工作树和 origin，读取 AGENTS.md、docs/PROJECT_NAMING.md、docs/records/HANDOFF.md 及相关目录指令。保留所有未提交工作，不执行 reset --hard、clean、强制推送或自动覆盖。

在远程匹配上述仓库时 fetch origin。工作树干净且当前 main 可以快进时，使用 git pull --ff-only 同步；存在本地修改、分叉或正在其他开发分支时，先查看 origin/main 的命名提交，采用不会覆盖当前工作的最小同步方式，遇到实际冲突再说明具体冲突。不要自动提交、推送、改名远程仓库或重命名本地目录。

同步后检查：根 README.md 的正式名称、docs/PROJECT_NAMING.md 的约定、docs/README.md 的入口、AGENTS.md 的项目身份、HANDOFF 的当前命名，以及 game/project.godot 的 config/name 应为 \"GreyLine Taskforce\"。如果这些变更已经存在，不重复实施；只修正本地仍存在的用户可见旧标题，逐项检查，不全局替换。

保留现有脚本类名、资源路径／UID、正式 DATA、数据和规则版本、回放结构／冻结夹具及历史记录语境。不要将旧文件名 RTT_GAME_DATA.xlsx 或 RTTGame_DESIGN_PRINCIPLES.md 改名，不补造缺失文件。此次不实现新玩法、不改平衡、不继续 0.6 战斗代码，不更新 AUTONOMOUS_DESIGN_REVIEW.md。

Godot 项目改名可能改变默认 user:// 目录；先核对已有本地保存与回放文件位置，报告迁移影响，不自动迁移或删除数据。运行 git diff --check；若有 Godot，可按现有约束做无界面编辑器导入检查，不启动客户端或服务端，不声称人工验收通过。最终报告同步的提交、修改文件、检查结果及保留的历史工程标识。
