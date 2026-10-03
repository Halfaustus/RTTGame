# Prototype 0.2A：基础自动交战与死亡同步

0.1D、0.2A 均已由用户明确确认手动验收通过；下文自动验证记录与人工验收清单保留，不补写用户未提供的逐项结果。

## 实现

- `UnitState` 保存 owner、team、最大/当前生命值和可为空的单武器。`UnitDefinition` / `WeaponDefinition` 分离数据与行为。
- `prototype_combat.tres` 设置玩家 team 1、叛军 team 2、三名静止叛军出生点，以及每玩家的单位定义顺序。玩家三单位依次为移动射击、停步射击、无武器；均为 100 HP。两把武器均为 8 m 射程、10 伤害、1 s 射击间隔。
- `CombatSimulation` 只由服务器调用。按单位中心距离寻找最近可见存活敌人，同距按 ID；不同 owner 的同队单位不会互相攻击。视线检查共享地图的真实三维障碍盒，不采用移动导航的膨胀净空。
- 每个服务器物理 tick 先推进已有移动，再交战。按射手 ID 顺序立即结算伤害；同 tick 已死亡者不能继续射击。每武器有独立移动射击资格，冷却在移动期间继续推进。到达后即可满足停步射击条件。
- 生成/晚加入使用可靠有序的完整单位快照；射击、生命值和死亡使用服务器 authority RPC。位置仍向所有客户端复制，移动路径仍只发送所有者。快照字段：`unit_id`、`owner_peer_id`、`team_id`、`position`、`maximum_health`、`health`。射击字段：`attacker_id`、`target_id`、`start`、`end`、`health`（结算后目标生命值）。死亡消息为 `unit_id`。
- 死亡立即从战斗、移动及服务器存活表移除，并删除待复制位置。客户端先隐藏/清理选择和路径再释放节点；死亡 ID 拒绝迟到生成，位置/生命值更新只作用于已有单位。
- 单位复用原场景；玩家蓝色、叛军红色，立体条显示当前生命值比例，黄色射击线保留 0.12 秒。表现不执行伤害。

## 修改文件

- `game/scripts/units/unit_state.gd`、`unit.gd`，新增 `unit_definition.gd`。
- `game/scripts/movement/movement_simulation.gd`：增加移动状态查询与死亡移除。
- `game/scripts/networking/network_manager.gd`：服务器交战、叛军、快照与事件同步。
- `game/scripts/core/game_world.gd`，新增 `shot_visual.gd`：生命值/阵营/射击表现和死亡清理。
- 新增 `game/scripts/combat/{weapon_definition,combat_config,combat_simulation}.gd`。
- 新增 `game/data/{prototype_combat,unit_mobile,unit_stationary,unit_unarmed,weapon_mobile,weapon_stationary}.tres`。
- 新增 `game/tests/prototype_02a_test.gd`；B/C 原有测试服务器夹具跳过叛军，保持移动测试 ID 假设。
- 新增 GDScript 对应 `.gd.uid` 为 Godot 源资源标识；未加入 `.godot` 缓存。
- 更新 `docs/HANDOFF.md` 并新增本文。

## 验证记录与复跑

下列检查通过，退出码 0；未启动窗口或 headless 客户端：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --editor --import --quit
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_02a_test.gd
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01b_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01c_test.gd -- --test-role=simulation
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --script res://tests/prototype_01d_test.gd
git diff --check
```

0.2A 覆盖同队不同 owner、最近目标与同距 ID、射程/死亡/无武器过滤、墙和方块遮挡、实际障碍边缘和高度、双方开火、冷却、移动资格、不中断命令、死亡移除与死后命令拒绝、服务器存活快照/当前生命值/不重生叛军、客户端选择/路径清理、防复活及射击线到期释放。

沙箱仍输出根证书读取、user:// 日志写入和编辑器设置保存权限错误；修正新增资源 BOM 编码和测试夹具类型后，最终运行没有脚本/资源错误。实际 ENet 双客户端和 Linux 服务器未在本轮运行。

## 双客户端手动验收

在项目根目录分别启动服务器与两个客户端；每条命令使用一个独立终端：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --headless --path game --log-file "$env:TEMP\RTTGame-02A-server.log" -- --server
& "C:\Dev\Godot\Godot_console.exe" --path game --log-file "$env:TEMP\RTTGame-02A-client1.log"
& "C:\Dev\Godot\Godot_console.exe" --path game --log-file "$env:TEMP\RTTGame-02A-client2.log"
```

每项需要新场景时，先关闭本轮两个客户端窗口，并在服务器终端按 Ctrl+C，再重新启动。不要按进程名批量结束 Godot。手动启动与停止脚本已按用户要求删除。

1. 初始两端应各看到相同的 9 个单位：6 蓝、3 红，全满血。两个玩家蓝色同队，不能控制对方蓝色或红色。双方靠近也不互射。
2. 每玩家按生成顺序的三个单位分别为移动射击、停步射击、无武器。第一玩家初始位置为世界 X=-3、0、3 / Z=100；第二玩家为 X=-3、0、3 / Z=97。叛军位于 (-3,90)、(3,90)、(8,90)，owner 为 0。
3. 将左侧蓝色武装单位移到主墙南侧、距红色不足 8 m 的位置，例如 (-3,96)。墙仍隔在 (-3,90) 叛军之间，不能隔墙射击。绕到墙侧并进入无遮挡射程后，应自动互射，两端看到相同血量变化和短暂黄色射击线。方块 X=[5,7] / Z=[89,92] 同样不得被射击线穿过；靠近测试时注意其他敌人可能仍有无遮挡视线。
4. 给左侧移动射击单位下达途经敌人附近的普通移动命令，观察移动中射击、既有路径继续执行；再用中间停步射击单位重复，确认移动中该单位不开火，停下后开火。无武器单位靠近敌人可受伤但始终不开火。叛军只站立开火，不追击离开射程的玩家。
5. A 操作时，移动虚线仅 A 可见，B 同时看到射击线和血量变化；B 操作时反向核对。无需选择单位也应显示交战表现。
6. 将己方单位选中并命令其在敌人火力下移动，等其死亡；两端同时移除该单位，所属客户端清除选择标记和整条路径。继续右键不会命令死者；后续位置消息不会令其重现。击杀叛军后也应在两端移除。
7. 在至少一名叛军死亡、另一存活单位受伤后，将己方单位移出射程以保持状态稳定；关闭 B，再单独启动一个客户端。新客户端应只看到当前存活单位，其阵营、位置和剩余血量与 A 一致；已死亡叛军不得恢复。重连仍会给新 peer 生成三名新蓝色单位，断线玩家原存活单位保留并停止移动。额外启动的客户端需单独关闭。

晚加入客户端命令（仍在项目根目录；日志保存在项目外）：

```powershell
& "C:\Dev\Godot\Godot_console.exe" --path game --log-file "$env:TEMP\RTTGame-02A-late-client.log"
```

## 限制

仅单武器、静态轴对齐障碍、即时命中；单位不遮挡射击，不追击、不主动改变移动。目标扫描采用简单遍历，需扩大规模时先测量性能。当前按稳定射手 ID 顺序结算，同 tick 先死亡者不反击；每 tick 每武器至多一发。断线单位继续遵循自动交战规则，但停止移动。未实现用户排除的任何移动、战斗或任务扩展。
