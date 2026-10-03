# 人工验证清单

0.2 已由用户完成人工验收并保存，用户确认 0.3B 完成；当前新增项见 [0.3C 清单](PROTOTYPE_03C.md)。start-replay.ps1 / stop-replay.ps1 独立管理离线回放进程，支持正式文件和 player_id，已有自动 1× 播放入口；暂停/倍速/跳转未实现。联机脚本仍支持录制与正常收尾，默认停止需确认退出码和回执，强制停止不算成功。下方清单/证据是 0.2 历史记录，不作为 0.3C 人工通过记录。

最新游戏键位与镜头／编队组合操作见 [0.2H 清单](PROTOTYPE_02H.md)，完整基础项见 [0.2 统一清单](PROTOTYPE_02F.md)。当前 E 停止、Q 攻击、WASD 镜头平移；右键释放确认。0.2H 自动检查通过，待人工验收；以下启动脚本证据为此前实测。

两份脚本已实际保存：`scripts/start-local-test.ps1`、`scripts/stop-local-test.ps1`。下列“脚本检查通过”不等于游戏人工验收通过。

| 操作步骤 | 预期结果 | 实际状态 |
| --- | --- | --- |
| 运行启动命令，观察两个客户端 | 生产入口启动隐藏服务器、两个可见窗口客户端；均连接服务器 | 脚本检查通过；server PID 4552、client-A 33028、client-B 42224；两个窗口可见，连接日志齐全 |
| 本轮会话运行时再次启动 | 检测 UDP 7777 占用，不生成第二组三进程；保留失败记录 | 自动检查通过；失败记录内 Processes=[] |
| 停止脚本读取启动时间被修改的记录 | 拒绝停止身份不匹配的 PID，进程仍运行 | 自动检查通过；identity-mismatch-left-running |
| 按会话文件停止，再重复停止 | 仅关闭该会话三进程，重复停止报告 already-exited，保留全部日志 | 自动检查通过；最终三进程均已结束，7777 可重新绑定 |
| 停止本轮会话，观察另一个独立 Godot | 不按全局 Godot 名称误杀其他会话 | 自动检查通过；18888 独立服务器在本轮停止后仍运行，随后由验证者按其自有 Process 对象清理 |
| 启动过程中遇到错误 | 清理本轮已启动进程，记录 failed-cleaned，保留日志 | 自动检查通过；初轮日志共享读取失败后 PID 7900 已清理；读取逻辑修正后完整启动/停止通过 |
| 左键选择/框选，Q/F/R 后右键，Esc/S | 左键不确认指令；Q 攻击、F 快速、R 倒车均右键确认后退出；Esc 取消；S 停止 | 待游戏人工验收；本轮仅验证脚本 |
| 按 [0.2 统一清单](PROTOTYPE_02F.md) 检查路线、速度、交战、倒车和两窗口同步 | 满足统一清单各项预期，无卡顿或显示回退 | 待游戏人工验收；启动脚本没有替代这些操作 |

启动脚本的 `-GodotPath` 支持主程序或同目录 `_console.exe` 包装器，包装器解析为真实主程序以正确记录和停止 PID。生产参数为服务器 `--headless -- --server`，客户端 `--windowed`；项目和独立日志使用 `--path`、`--log-file`。不会修改系统权限、持久环境变量或游戏键位。

停止无参数时使用 `tmp/local-test/latest-session.json` 指向的最近成功会话；要停止指定会话使用 `-SessionFile`。PID、UTC 启动时间、实际可执行文件和进程名均匹配才停止，记录中保存角色、完整参数、项目及日志身份。记录不匹配或停止失败时保留该进程并报错；不要手动将其他 PID 填入记录。

# 验证证据

最终成功会话目录：`C:\Projects\RTTGame\tmp\local-test\20261003-201044-2aaadb9d55cc427a831ee4b632a98ba1`。

- `server.log`：`Dedicated server started on port 7777.`、两次 peer connected 及单位生成。
- `client-A.log`、`client-B.log`：各自 `Connected to server. Local peer ID:` 及服务器快照。
- `session.json`：三份 PID、StartTimeUtc、ExecutablePath、ProcessName、Arguments、LogPath、SessionId 记录。
- `launch-verification.json`：生产启动、两客户端连接及窗口句柄。
- `window-verification.json`：server WindowVisible=false，client-A/client-B WindowVisible=true。
- `stop-20261003-201746-232.json`：三进程 stopped；`stop-20261003-201746-261.json`：三进程 already-exited。
- `final-verification.json`：两窗口可见、两客户端连接、会话停止、重复停止、端口释放；明确 GameplayManualAcceptance=not performed。启动与最终验证调用退出码均 0。

保护检查目录：`C:\Projects\RTTGame\tmp\local-test\20261003-200638-d049bdfcad954e9a943cff8de4d41ec0`，`stop-verification.json` 记录端口拦截、身份拒绝、仅本轮停止、其他 Godot 保留、重复停止及端口释放，全部 true；调用退出码 0。

占用拒绝记录：`tmp/local-test/20261003-200747-ca01fd44b9b240fb9f59cf13f917f90d/session.json`，Status=failed-cleaned，Processes=[]。初轮失败后清理证据：`tmp/local-test/20261003-200604-ec08172e0ef9464ba28fdac818856ec7/session.json`，记录 server PID 7900、Status=failed-cleaned，进程不存在。后续修复后的完整启动与停止证据以上述最终成功目录为准。

未验证项：游戏人工操作、渲染/转向/射击观感、下令卡顿及 [统一人工清单](PROTOTYPE_02F.md) 中未验收项；没有截图或人工通过记录。

`tmp/` 已命中现有 Git 忽略规则，日志与会话记录不进入 Git；本页保留必要结果、参数、退出码摘要。脚本及文档尚未提交或推送。

# 准确的启动／停止命令

在 `C:\Projects\RTTGame` 的 PowerShell 执行。启动脚本输出日志目录和带精确 SessionFile 的停止命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-test.ps1 -GodotPath 'C:\Dev\Godot\Godot.exe'
```

停止最近成功启动的会话：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1
```

停止指定会话（将路径替换成启动输出的 SessionFile，不需要修改脚本）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1 -SessionFile 'C:\Projects\RTTGame\tmp\local-test\20261003-201044-2aaadb9d55cc427a831ee4b632a98ba1\session.json'
```

也已验证 `-GodotPath 'C:\Dev\Godot\Godot_console.exe'` 可正确解析并启动主程序。可用 `-StartupTimeoutSeconds 60` 调整启动等待时间；超时会清理本次启动的进程并保留会话/日志。
