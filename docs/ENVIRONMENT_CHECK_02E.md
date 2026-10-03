# 0.2E 环境报错与验证核对

状态：自动检查通过，待人工验收。此次未改游戏代码、系统权限或机器/用户级环境变量，未使用管理员权限，未启动客户端。

## 原始命令、报错路径与退出码

工作目录为 `C:\Projects\RTTGame`，实际使用 Godot 4.7.2。

```powershell
& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --script res://tests/prototype_02e_test.gd
# 本次复现：原生进程退出码 0，打印 Prototype 0.2E isolated reverse checks: PASS

& 'C:\Dev\Godot\Godot_console.exe' --headless --path game --editor --import --quit
# 本次复现：原生进程退出码 0，导入完成，无脚本/资源错误
```

| 报错 | 路径/接口 | 涉及命令 | 影响 |
| --- | --- | --- | --- |
| Failed to open log file for writing / 日志轮转失败 | `user://logs/godot.log`，本次轮转目标 `user://logs/godot2026-10-03T19.15.41.log` | 默认日志路径的隔离测试；之前其他隔离检查也有同类输出 | 默认文件日志不可用，控制台仍有结果；不阻止测试执行 |
| Cannot save file / Error saving editor settings | `C:/Users/30731/AppData/Roaming/Godot/editor_settings-4.7.tres` | 编辑器导入 | 无法保存编辑器用户设置；项目导入仍完成 |
| Failed to read the root certificate store | Godot `get_system_ca_certificates`，Windows 根证书存储接口，未报告文件路径 | 上述两类命令及本次所有 Godot 复核 | 不能据此确认是权限原因；记录为证书读取环境问题，不影响本次离线模拟、导入及 ENet 本地服务器启动。HTTPS/TLS 未验证 |

通过临时离线路径探针确认，原始 `user://` 实际为：

`C:/Users/30731/AppData/Roaming/Godot/app_userdata/New Game Project/`

因此原始日志完整路径为该目录下的 `logs/godot.log` 及时间戳轮转文件。探针退出码 0，日志位于项目内 `tmp/permission-audit/path-probe.log`。项目当前 config/name 为 `New Game Project`，本次未更改名称或用户目录设置。

## 项目内可写目录处理

已实际验证有效：

- 检查子进程继承的 `APPDATA` 指向 `C:\Projects\RTTGame\tmp\permission-audit\appdata`。
- `LOCALAPPDATA` 指向 `C:\Projects\RTTGame\tmp\permission-audit\localappdata`。
- 每条命令显式提供项目内 `--log-file`，独立保存日志。
- 编辑器成功创建 `appdata/Godot/editor_settings-4.7.tres`（17746 字节）及本地缓存；日志写入与编辑器设置保存报错均消失。
- 在 PowerShell `try/finally` 中恢复原始进程环境变量，没有设置持久环境变量，也没有修改 ACL。

`tmp/` 已在现有 .gitignore 中排除，本次未改 .gitignore。证据保留在 [results.json](/C:/Projects/RTTGame/tmp/permission-audit/results.json)：含逐项完整命令、日志路径、Godot 原生退出码，以及 PASS/脚本错误/环境错误检索结果。同目录 `<检查名>.log` 是 Godot 日志，`<检查名>-console.txt` 是捕获控制台输出。

例如可复制如下流程（不创建启动脚本）：

```powershell
$rttAuditRoot = 'C:\Projects\RTTGame\tmp\permission-audit'
$rttOldAppData = $env:APPDATA
$rttOldLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $rttAuditRoot 'appdata'
    $env:LOCALAPPDATA = Join-Path $rttAuditRoot 'localappdata'
    foreach ($rttDirectory in @($rttAuditRoot, $env:APPDATA, $env:LOCALAPPDATA)) {
        [IO.Directory]::CreateDirectory($rttDirectory) | Out-Null
    }
    & 'C:\Dev\Godot\Godot_console.exe' --headless --path 'C:\Projects\RTTGame\game' --log-file "$rttAuditRoot\editor-import.log" --editor --import --quit
    Write-Host "编辑器退出码：$LASTEXITCODE"
    & 'C:\Dev\Godot\Godot_console.exe' --headless --path 'C:\Projects\RTTGame\game' --log-file "$rttAuditRoot\02e.log" --script res://tests/prototype_02e_test.gd
    Write-Host "0.2E 退出码：$LASTEXITCODE"
} finally {
    $env:APPDATA = $rttOldAppData
    $env:LOCALAPPDATA = $rttOldLocalAppData
}
```

## 本次实际复核结果

下表每条 Godot 命令都使用上述临时环境和 `--log-file C:\Projects\RTTGame\tmp\permission-audit\<检查名>.log`。每次调用后立即读取 `$LASTEXITCODE`，不是使用整个 PowerShell 批处理最终退出码替代。完整参数在 results.json。

| 检查名 | 命令追加参数 | 原生退出码 | 状态 |
| --- | --- | --- | --- |
| editor-import | `--editor --import --quit` | 0 | 导入完成，通过 |
| input | `--script res://tests/command_input_test.gd` | 0 | PASS |
| 02a | `--script res://tests/prototype_02a_test.gd` | 0 | PASS |
| 02b | `--script res://tests/prototype_02b_test.gd` | 0 | PASS |
| 02c | `--script res://tests/prototype_02c_test.gd` | 0 | PASS |
| 02d | `--script res://tests/prototype_02d_test.gd` | 0 | PASS |
| 02e | `--script res://tests/prototype_02e_test.gd` | 0 | PASS |
| 01b | `--script res://tests/prototype_01b_test.gd -- --test-role=simulation` | 0 | PASS |
| 01c | `--script res://tests/prototype_01c_test.gd -- --test-role=simulation` | 0 | PASS |
| 01d | `--script res://tests/prototype_01d_test.gd` | 0 | PASS |
| server-smoke | `--script res://tests/prototype_01d_test.gd -- --server-smoke` | 0 | PASS，独立服务器端口 17779 启动并结束，无客户端 |
| diff | `git diff --check` | 0 | 通过；仅提示 HANDOFF 的 LF/CRLF 转换警告 |

全部 Godot 命令仍打印根证书读取错误；全部没有日志/编辑器设置写入错误，没有 SCRIPT ERROR 或 FAIL；所有测试均打印 PASS。证书读取失败不使退出码非零，但本次通过判断同时依据明确测试结果，未仅凭退出码判断。

## 失败、修复及跳过的边界

- 本次环境复核没有失败的功能检查；根证书读取仍失败，单独记录为环境问题。
- 0.2E 开发初轮曾失败的折点净位移/最终朝向检查和测试数组类型错误已修正，不应归为权限环境问题。数组类型错误导致测试无法正常完成，当时中断了运行；本次已完整通过。
- 0.2E 上一轮 0.2A 射击线释放检查曾真实失败（测试退出码 1）；调整 deferred queue_free 的测试等待时序后通过。本次 02a 原生退出码 0、PASS，不将原失败隐藏为环境噪声。
- 先前输入复核误用 `--test-role=selection`，入口断言后中断，并非成功检查；随后正确 `--test-role=simulation` 已通过，本次再次确认。没有连接客户端。
- 按用户要求跳过人工验收及双客户端端到端测试，包括两窗口位置/朝向显示、实际转向观感、下令卡顿体验和晚加入联网演示。隔离快照/表现检查不替代这些测试。
- Linux 专用服务器构建/运行和 HTTPS/TLS 检查未执行；本次 Windows 独立服务器 ENet 启动通过不代表这两项通过。

结论：本次已执行检查的结果不受日志、编辑器设置或证书环境报错影响；日志与编辑器设置问题已通过项目内目录解决，剩余证书读取报错记录为环境问题。0.2E 仍为“自动检查通过，待人工验收”，不记录为人工通过。
