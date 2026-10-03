# 人工验证清单

历史 0.4A 记录；当前 UI、订单状态及整数分数约束已由 [0.4B](PROTOTYPE_04B.md) 更新。旧 40.5 测试价格不再合法，当前为 40；以下数据与 ENet 证据对应当时的实现，不代表当前 0.4B 人工或联机验收。

**自动检查通过，待人工验收。** 本轮为底层接口，没有兵牌、倒计时或购买 UI，不能在生产窗口中点击购买。接口检查已经通过隔离测试与真实 ENet 完成，不能记为人工验收通过。

| 操作步骤 | 预期结果 | 实际状态 |
| --- | --- | --- |
| 启动下方双窗口会话，检查单位与敌军 | 沿用原服务器测试生成，每人原有三单位；叛军仅服务器生成，不出现订单生成单位 | 真实 ENet 自动通过；窗口观感待人工 |
| 在两个窗口分别选己方，右键基本移动；F/Q/R 后右键；E 停止，再下令 | 基本/快速/攻击/倒车、停止继续工作，路线仅所属玩家可见；位置/朝向和伤亡双方一致 | 四模式、停止、死亡同步 ENet 自动通过；键鼠/显示待人工 |
| 左键选择、右键释放确认、Esc 取消；WASD/中键或 Alt/滚轮操作镜头 | 原 0.2H 输入和镜头行为保持，不因新接口改变 | 输入代码未修改；人工组合操作未执行 |
| 查阅部署数据；调试器观察 NetworkManager.local_deployment_state | 稳定目录和出生点 ID、原配置引用、临时价格/上限明确；账户初始 1000，每完整 5 秒 +25；只存在本人的订单 | 自动通过；无经济 HUD，人工数据核对待验收 |
| 查阅经济测试与真实 RPC evidence 的扣费/限额/退款结果 | 300/150/40.5 为出动价格；40.5 后保留 .5，显示去尾；在场＋pending 限额；非法/非本人请求不改变账户；重复取消只退款一次 | 50 项隔离断言及真实 ENet 自动通过；人工审阅待验收 |
| 查阅点合法性、尺寸与障碍检查，区分 point_id 和 destination | 服务器数据决定出生坐标和 yaw；未知/越界/无效定义拒绝；目的地不是出生点；允许阵营/预留类别限制生效 | 自动通过；没有实际部署入口 |
| 查阅出生受阻行为边界 | 临时规则：合法点受阻仍保留已付费 pending 订单和名额；实际选位、等待及生成在 0.4C 执行 | 接口边界自动通过；实际等待/生成未实现、未验证 |
| 查阅维护费报价与回放边界 | 地面单位本体出动分每分钟 5% 仅报价，不扣费；经济/订单不写 RTTReplay v1，旧冻结夹具不变 | 自动通过；维护扣费留 0.4D；本轮不扩展回放 |

接口契约：客户端调用 `NetworkManager.request_deployment(config_id, point_id, destination)` 或 `request_cancel_deployment(order_id)`，没有传入 player_id/价格/出生坐标的参数。服务器收到 RPC 后按真实 sender 获取 player_id，tick 消费时再次验证连接与映射；移动与部署分别保留各自 FIFO，不依赖跨接口的网络回调即时修改状态。服务器先结算到期收入，再执行订单，随后移动、战斗和复制。

目录临时数据：test.armored（车辆，价值 500/出动 300/上限 4），test.rifle（步兵，200/150/6），test.unarmed（步兵，50/40.5/8），宽度均 1m。现有免费测试单位计入各卡在场数量，仍无费用。ground.west=(-12,0.5,112)、ground.east=(12,0.5,112)，yaw=0，允许当前测试玩家阵营 1；类别限制 [] 为通用地面。阵营编号当前与队伍 1 对应，不是玩家身份；不同玩家仍同队。

账户保留离线历史身份并继续 tick 收入；只有当前绑定该 player_id 的连接收到状态。新连接保持原有新身份行为，不恢复旧账户控制权。本轮不做重连专项。`deployment_event` 提供当前经济流 tick/sequence 和深拷贝载荷，与 RTTReplay v1 记录流互相独立；`export_player`/`export_state` 返回原生 Dictionary/Vector3 状态，不构成回放扩展、文件格式或存档加载接口。

# 验证证据

- `tmp/04a/import.log`：Godot 编辑器导入退出 0，无脚本解析错误。
- `tmp/04a/unit.log`、`unit-results.json`：50 项断言，0 失败，包含收入边界/补结算/晚注册、余额不足、限额、重复取消、非法 ID/目的地、账户隔离、价格与小数、维护报价、部署点阵营/类别/高度/尺寸/阻挡，以及断连/被复用 peer 的旧请求拒绝。首轮余额不足用例先置余额算错，修正测试后通过。
- `tmp/04a/regression-results.json` 与对应日志：02B 停止、02G 朝向/编队、03A 冻结兼容、03B 录制、03C 离线兼容检查均退出 0。未重复未受影响的全量旧测试或窗口脚本测试。
- `tmp/04a/enet-000300/process-results.json`：生产服务器＋两 headless 客户端三个退出码为 0；`economy-driver.json` / `economy-limit.json` / `economy-observer.json`：真实 RPC 扣费、限额、余额不足、重复取消、非法请求与他人订单拒绝；`economy-driver-final.json` / `economy-observer-final.json`：各自只收到自己的 player_id，收入后 1025、pending=0；driver/observer 日志与结果文件：四种移动/停止/双方射击和死亡。
- 同目录 `match.rttreplay.json` / `server-final.json` / `audit.log`：完整 v1 文件为 496 tick / 807 records / 9 快照，6 次原测试单位 spawn、15 shot / 1 death，与独立服务器捕获的记录、header、最后快照、tick/count 一致；经济订单未进入 v1。进程已结束，UDP 7777 可重新绑定。冻结 `game/tests/fixtures/replay_v1.json` SHA-256 保持 `F6B92FEE52250310AC7D13EDBDDC64F50142F3233A8FE6691B1F38BE6763CF15`；原地图/规则标识与 8 文件表现指纹保持不变，旧实际录制兼容检查通过。
- 受限环境首轮真实 ENet helper 退出 1，路径 `tmp/04a/run-enet.ps1` 行 20 无法访问子进程环境字典，未启动进程；批准重跑退出 0。离线 Godot 日志根证书环境提示不影响本轮无 TLS 检查。临时 APPDATA、日志、进程证据和真实录制在已忽略 `tmp/`，未改系统权限。
- 未执行人工键鼠与窗口画面验收、Linux 检查。实际生成/受阻等待、维护收费、购买 UI 未实现；没有用模拟通过替代这些事项。现有启动/正常停止脚本未修改，沿用之前真实验证过的生产入口与身份保护。

# 准确的启动／停止命令

从 `C:\Projects\RTTGame` 执行，启动服务器和两个可见客户端（UDP 7777 必须空闲）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-test.ps1 -GodotPath 'C:\Dev\Godot\Godot.exe'
```

正常停止最近一次成功会话，只管理该会话记录的进程：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1
```

接口自动断言可复查（不启动客户端，不等于人工验收）：

```powershell
New-Item -ItemType Directory -Force .\tmp\04a\appdata, .\tmp\04a\localappdata | Out-Null
$env:APPDATA = 'C:\Projects\RTTGame\tmp\04a\appdata'
$env:LOCALAPPDATA = 'C:\Projects\RTTGame\tmp\04a\localappdata'
& 'C:\Dev\Godot\Godot_console.exe' --headless --path .\game --script res://tests/prototype_04a_test.gd
```
