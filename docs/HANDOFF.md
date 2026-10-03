# RTTGame 开发交接

更新日期：2026-10-03（Asia/Shanghai）。本次收尾只新增此记录，没有添加功能、启动客户端、暂存、提交或推送，也没有删除或撤销原有修改。

## 当前阶段

Godot 4.7.2 / GDScript，专用服务器权威架构。当前为 Prototype 0.1D：基础寻路与静态障碍绕行已实现，自动检查通过，双客户端人工验收待进行。

| 阶段 | 今天完成的内容 | 验证状态 |
| --- | --- | --- |
| 基础联网与生成 | headless 专用服务器、ENet 本机连接、服务器分配 ID 和归属、生成广播、晚加入同步、Unit 脚本移至 scripts/units | 已有联网检查；用户提供稳定运行记录 |
| 0.1A | 本机所属单位点击选择与选择标记 | 已有检查；后续由 0.1C 扩展 |
| 0.1B | 客户端移动命令、真实发送者归属验证、服务器移动、位置同步、晚加入当前位置、断线停止 | 用户明确记录“已完成并审查通过”；本次纯模拟回归通过 |
| 0.1C | 选择集合、框选、每玩家三个单位、多单位命令、稳定 ID 顺序落点；随后改为世界 X 方向一横排、仅所属客户端显示虚线路径 | 用户明确记录“已通过手动验收”；本次纯模拟回归通过 |
| 0.1D | 静态墙与障碍、服务器 A* 网格路径、绕行、路径替换、可达落点检查、障碍内目标附近回退、失败保留旧命令 | 本次离线检查通过；此前服务器独立启动检查通过；尚无用户双客户端验收记录 |
| 本地测试工具 | 一键服务器加两个窗口客户端、分开日志、等待就绪、UDP 7777 占用检查、进程身份记录、仅关闭本轮进程 | 之前启动、端口冲突、身份不匹配保护、重复停止及不影响其他 Godot 的检查通过；本次 PowerShell 语法检查通过 |

人工验收只依据会话中用户已提供的记录，不把自动检查当作人工验收，不补填未提供的具体操作结果。

## 当前实现与文件职责

- `game/scripts/networking/network_manager.gd`：Autoload。只有服务器分配 unit_id 和 owner_peer_id；移动 RPC 使用真实发送者逐个校验、过滤无效或非本人 ID。生成与位置由服务器复制，路径仅发送给对应所有者。
- `game/scripts/units/unit_state.gd`：权威运行时单位状态；`game/scripts/units/unit.gd` 仅承担视觉表现及选择标记。
- `game/scripts/movement/movement_simulation.gd`：服务器移动命令及沿路径推进。无有效路径的单位保留旧目标、旧路径和进度。断线停止该玩家单位，当前不删除其单位。
- `game/scripts/movement/static_navigation_grid.gd`：同步初始化 AStarGrid2D，服务器监听前完成。按单位半宽加余量扩大静态障碍，检查完整路径线段，避免切墙角；不依赖客户端相机或异步导航烘焙。
- `game/scripts/core/game_world.gd`、`selection_rectangle.gd`、`movement_path_visual.gd`：本地点击、框选、所属单位验证及剩余虚线路径显示。选择不发送到服务器；客户端不提交路径、不执行权威移动。
- `game/data/prototype_movement.tres`：速度 4 m/s，复制间隔 0.05 s，每玩家 3 单位，单位宽 1 m，落点间距 1.5 m，导航格 0.5 m，障碍余量 0.05 m，附近目标搜索半径 2 m。地图 X 范围 [-20,60]、Z 范围 [80,120]。
- `game/data/prototype_map.tres` 与 `game/scripts/maps/`：共享静态障碍数据及对应可见几何、碰撞体。主墙 X=[-4,4]、Z=[93.5,94.5]；另一障碍 X=[5,7]、Z=[89,92]；高度 2.5 m。
- 实际世界场景仍是 `game/scenes/maps/test_world.tscn`，增加 StaticMap 节点。Camera3D 设置保持原样。
- 多单位先按稳定 ID 分配世界 X 横排；遇到障碍时分别寻找可行走且可达、彼此间隔足够的附近终点，因此回退后可能不保持完全笔直的一排。

## 本次自动检查

以下检查在收尾时重新运行，均退出码 0，没有启动任何客户端：

1. Godot headless 编辑器导入：没有脚本或资源解析错误。
2. 0.1B 纯模拟：归属和目标拒绝、速度、到达、重定向、断线停止。
3. 0.1C 纯模拟：ID 排序、去重、混合归属、非法目标、横排及边界处理。
4. 0.1D 离线测试：导航未就绪、出生点、墙绕行及连续净空、到达停止、途中换命令、障碍目标回退、组落点、地图边界、隔离区域不可达及旧命令保留、碰撞数据和折线虚线表现。
5. 四个 PowerShell 脚本的语法解析；文档写入后运行 `git diff --check`。

此前 0.1D 还通过了仅服务器的 headless 启动检查，使用隔离端口 17779，不连接客户端。本次未重复该联网检查。

环境问题：沙箱内 Godot 输出根证书存储读取失败、user:// 日志写入失败，以及编辑器设置保存权限错误。上述检查仍通过，未出现脚本或资源错误；不能将输出描述为完全无 ERROR。Linux 专用服务器尚未验证。

## 已知限制与待验证事项

- 0.1D 的两个实际客户端路径显示、位置一致性、晚加入和断线行为尚待人工验收；之前 B/C 的验收不能替代 D 的回归验收。
- 当前为平面、静态、轴对齐障碍与 0.5 m 网格；没有动态单位避让，途中单位可以相互穿过；狭窄通道受网格和单位净空限制。
- 障碍内终点只在 2 m 范围寻找替代位置；无法找到路径时保留该单位旧命令。整排无法容纳于地图时拒绝命令。
- 右键目标由地面平面投影获得。验证障碍内目标时应点击墙脚对应地面位置，点击墙上部不一定映射到墙内。
- 断线单位保留并停止，重连获得新 peer 和新单位；尚无重连恢复或生产系统。
- 不添加战斗、动态避障、其他移动模式、控制组或编队朝向。后续功能须另行确定范围。

## 启动与停止（Windows PowerShell）

在 `C:\Projects\RTTGame` 执行同一条快捷命令；只有用户要求客户端测试时才运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-test.ps1 -GodotPath "C:\Dev\Godot\Godot_console.exe"
```

启动器自动定位项目，读取现有 DEFAULT_PORT（当前 UDP 7777），使用项目现有入口：服务器 `--headless -- --server`，客户端无额外角色参数，连接 127.0.0.1。启动前端口占用时输出 PID 和进程信息并停止，不结束其他进程。服务器日志就绪后再启动客户端，并等待连接日志；失败时报告已创建进程及日志。

日志与进程清单保存到启动器打印的 `%TEMP%\RTTGame-local-<时间>-<唯一后缀>\`：`server.log`、`client1.log`、`client2.log`、`session.json`。启动器会打印包含实际路径的完整停止命令。复制该命令；也可在项目根目录执行下面的形式，将占位符替换为本轮打印的完整路径：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local-test.ps1 -SessionFile "<本轮完整 session.json 路径>"
```

停止脚本核对 PID、创建时间、可执行文件路径，只关闭清单中身份匹配的本轮进程。启动失败后也用该清单清理；不要通过进程名批量终止 Godot。自行额外启动的客户端不在清单中，应自行关闭。

## 下一轮任务及人工验收清单

下一步首先在用户明确要求后进行 0.1D 的一个服务器加两个客户端人工验收，并记录实际结果，再决定下一阶段；不自动提交。

1. 用上述启动命令启动，确认分别有日志且两个客户端看到同样的六个单位。
2. 在客户端 A 框选自己的三个单位，右键墙另一侧地面；两端都观察单位绕过墙，到达停止且不穿墙。虚线路径只在 A 可见；无遮挡终点保持一横排。
3. 在客户端 B 对自己的单位重复操作，核对所属玩家才能选择及命令，路径只在 B 显示。
4. 移动途中更换目标，观察替换旧路径；右键墙脚范围，观察终点落在附近可走地面；地图外命令应拒绝。无法到达保留旧命令已由隔离地图测试覆盖，当前默认地图不包含完全隔离区域。
5. 关闭一个客户端，观察服务器正常且该玩家单位停止；需要晚加入回归时重新启动一个客户端，核对现有单位当前位置与其他客户端一致。额外客户端需手动关闭。
6. 保存并检查三个日志，使用本轮 session.json 停止命令，只关闭本轮测试进程；再次启动前确认占用检测正常。

## 不启动客户端的检查命令

在项目根目录执行：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --editor --import --quit
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01b_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01c_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01d_test.gd
git diff --check
```

`scripts/test-prototype-01b.ps1` 与 `scripts/test-prototype-01c.ps1` 会启动 headless 客户端，同样需要用户明确要求才能运行，不能与上面的纯模拟检查混淆。

## Git 与文件检查

当前分支 `master`，HEAD `70ab89b`（Add repeatable local multiplayer test launcher）。今天已有基础项目、启动入口、联网、权威生成、选择及基础启动器提交；当前工作区还包含后续移动、框选、寻路、启动器安全增强和本交接记录，均未暂存。

收尾前为 5 个已跟踪文件修改、27 个未跟踪文件；本次新增本记录后为 5 个修改、28 个未跟踪文件。未暂存、未提交、未推送。完整逐文件状态以 `git status --short --untracked-files=all` 为准。

已检查已跟踪文件、工作区文件名及常见私钥/API key 特征：没有发现误加入的 .godot 缓存、导出产物、日志或明显敏感配置。`game/.godot/` 已被忽略；日志目录和 *.log 也有忽略规则，启动器日志位于 TEMP。`.gd.uid` 和 `icon.svg.import` 是应保留的 Godot 源资源身份/导入配置，不是 .godot 缓存。此检查不等同于全面的秘密扫描；没有删除、撤销或修改任何原有文件。

建议提交说明（由用户手动完成）：

```text
Implement Prototype 0.1B–0.1D movement and development handoff

- Add authoritative movement, local box selection and multi-unit orders
- Route units around static obstacles with validated reachable destinations
- Show movement paths only to the owning client
- Guard local test startup and stop only recorded session processes
- Add isolated regression tests and document validation and pending acceptance
```

人工记录：0.1B、0.1C 已由用户确认；0.1D 人工验收待完成。不要在提交说明中写成 0.1D 已人工通过。
