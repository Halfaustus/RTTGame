# 0.5F 人工复检实现与测量

基线DB-2026-10-06-37。本轮依据用户明确授权：修复极短轨迹越过炮口；调整400×400米TEST ONLY活动地图相机；M252先测量分析，不改正式DATA／g10／高支路／射程。文档迁移到constraints与records为并行工作区变动，本轮保留该布局与修改。不更新自主设计人工审查清单。

## A. Root Cause

**Projectile**：ProjectileVisuals没有对称绘制，原实现是head减当前速度方向乘配置长度；问题是未使用已飞行历史上限。900m/s配置可画21.6米，而极近距离可能只飞0.5米。0.12秒终止余辉复用同一错误几何，故也越过炮口。旧shot_visual只承担显式旧shot表现，未改；活动弹丸与Replay接口分离保持。

**M252**：WeaponDefinition为W_M252，AmmoDefinition（代码类名AmmoDefinition）为A_M252_HE。正式Workbook与db29.json的Ammo.Projectile_Speed_kmh=810，ConfirmedGameData.ammunition除以3.6，得到225m/s。Weapon行不另存权威初速；活动固定发射从所选Ammo读取速度。生成TEST ONLY实例补瞄准0.1秒、待发1、装填4秒及散布0.15米等缺项，未覆盖正式初速／射程。Workbook SHA256与导出source_sha256一致。Legacy Prototype05FConfig的ProjectileDefinition数值不进入活动链。

T任务被FixedFireScheduler识别后固定调用GravityBallistics.high；low解存在但不用于T。高解恰是固定速度可达方程的较大飞行时间根，100米约89.4°，并无固定apex、额外角度下限、飞行时长上限或全程净空约束。g=10为全局机制常数，求解与固定30Hz推进一致。1800米是独立正式武器资格上限，不是225m/s在g10下的数学极限；同高程无障碍最大水平可达约v²/g=5062.5米。近距离选高支路会近乎竖直上抛，时间接近2v/g=45秒。

**Camera**：活动场景只绑定独立movement资源，未绑定独立CameraConfig，继承prototype_camera.tres。观察距离6–60米，俯仰20–80°，最高实际高度约59.09米；平移固定18m/s，400米需22.22秒；滚轮固定每格2米。无edge-scroll或drag-pan，只有WASD平移，Alt／中键用于旋转。

## B. Implemented Changes

|文件|实际修改|
|---|---|
|game/scripts/core/projectile_snapshot_buffer.gd|增加仅客户端的累计网络折线距离及对应缓冲距离；trail_points沿已有快照历史逆向裁剪，不越过最早可用样本。最多8份状态保持，丢弃旧样本时同步丢弃对应距离；晚加入从首次当前状态起算，不造历史|
|game/scripts/core/projectile_visuals.gd|共享网格改为绘制被裁剪的历史折线并保持渐隐；首次零路径不画线但继续处理活动状态；终止用实际终止点接已有历史，同样裁剪，零路径不创建余辉；0.12秒参数不变|
|game/scripts/core/camera_config.gd|增加默认关闭的height_scaled_pan、maximum_pan_speed及zoom_distance_fraction，扩展编辑器距离范围；旧资源默认行为保持|
|game/scripts/core/local_camera.gd|选择启用后按实际相机高度线性缩放WASD速度；滚轮步幅max(原zoom_step,观察距离×比例)；焦点边界和地面计算保持|
|game/data/db37_active_test_camera.tres|独立TEST ONLY配置：距离6–500米，速度18–140m/s，高度缩放开，滚轮比例0.15，最低步幅2米|
|game/scenes/maps/db33_active_test_world.tscn|仅活动相机引用新资源；不改地图尺寸、movement资源或旧test_world|
|game/tests/projectile_history_clipping_test.gd|近程、单位／障碍／边界终止、零路径、曲线、晚加入、缓冲淘汰、多弹、真实网格顶点与Replay隔离专项|
|game/tests/active_camera_test.gd|低中高速度、缩放、地图四角可见、边界、跨图、ground picking与部署共用相机、旧场景回归|
|game/tests/m252_flight_measurement_test.gd|真实服务器T→FiringFrame→发射→模拟→地面terminal测量，无表现时间替代|
|game/tests/client_acceptance_fixes_test.gd|新增首次零历史不画尾迹断言，保留正常长度验证；测试终止时间晚于最新快照，避免制造不可能的服务器事件次序|

权威战斗代码、碰撞算法、终止position、DATA与网络协议均未修改。累计客户端网络弦长是保守的已知路径预算，不是新的服务器d_travel或战斗真值；真实重力历史保留折线弯曲，不用发射点到终点的一根直线冒充全程。缺快照／晚加入时可能显示更短尾迹，这是保守裁剪。视觉纠正仍仅影响head，裁剪不回写服务器。Projection六字段生成、四字段终止白名单保持；不增加来源、目标、Resource或私有信息。Replay实时挂接开关、冻结格式／manifest／fingerprint均保持。

## C. M252 Flight-Time Measurements

每个点实例化真实活动NetworkManager、保存的TEST ONLY炮组、正式Ammo，发送服务器T单点一发命令；正常转向／瞄准、FiringFrame、散布和固定步模拟都参与，不直接构造替代发射。记录实际spawn到实际地面impact的时间，apex和角度从实际采样发射向量解析得到。RNG为现有50506；不把指令到命中的瞄准时间混进飞行时间。

|Range（米）|Launch velocity（m/s）|Arc / angle|Apex（米，地面以上）|Flight time（秒）|>10s|
|---:|---:|---|---:|---:|---|
|100|225|high / 89.435°|2531.654|45.00065|是|
|150|225|high / 89.152°|2531.346|44.99791|是|
|200|225|high / 88.869°|2530.913|44.99405|是|
|250|225|high / 88.586°|2530.358|44.98911|是|
|300|225|high / 88.302°|2529.678|44.98307|是|
|350|225|high / 88.019°|2528.875|44.97593|是|
|1800*|225|high / 79.588°|2449.226|44.26189|是|

*400×400米活动地图最大几何跨度约565.7米，无法实测1800米。仅1800米夹具在内存复制MovementConfig并向+Z扩展边界，地形仍用原地图定义、原g10、DATA与实际服务器链；不修改任何生产地图文件。落点距武器1799.999米（向正式上限内收1mm以避免浮点边界拒绝），发射位置改到合法正向测量。100–350米全部使用保存的活动边界，测量线在x≈100避开原障碍。该扩展是隔离测量条件，不是新正式地图。

所有点由ground碰撞终止，没有固定10秒寿命或客户端提前落弹；散布仍是现有TEST ONLY0.15米。解析真实发射的到地时间与模拟时间差小于0.001秒。终止point在地面；terminal position仍用既有解析部分步，因此与碰撞弦线交点允许既有约1.39mm偏差，未为测量改终止语义。

当前正式DATA＋g10＋高支路在上述任何点都不能满足10秒。更一般地，同高程225m/s高支路即使到数学最远点也至少约31.82秒，正式100–1800米范围实际约44–45秒。低支路名义时间分别约0.444、0.666、0.888、1.111、1.333、1.556、8.133秒，但不等同获准改用低支路。

原始值与范围说明：tmp/db37-manual-recheck/m252-measurements.json；控制台证据m252-final.log。

## D. M252 Recommendation

**推荐先审议B／D的组合设计，未实施**：若近程节奏优先，明确是否允许距离相关装药／有效初速，再设计迫击炮profile，把10秒作为软目标。preferred_max_flight_time当前不在Weapon／Ammo Schema中；不能只加一个限制就产生违反固定225m/s的高解。profile、装药档位、选速与记录规则需要新设计授权和未来回放考虑。

以平地飞行T=10秒为例，水平速度约R/T，竖直速度约gT/2，所需总初速约sqrt((R/10)²+50²)：100米约51m/s、350米约61m/s，仰角约79°／55°，弧高约125米。改变的是实际服务器发射条件，不能只压缩客户端播放。正式数据尚未授权改动。

即使允许选速，若把间接高抛定义为至少45°，1800米理论最短仍为sqrt(2R/g)≈18.97秒；10秒下最多约500米。1800米／10秒需要约15.5°低弧，不能同时保留这种高抛语义。这里只用于说明取舍，不新增45°正式角度门槛。

- **A替代：改用低支路**可在现有速度下满足各采样点10秒，但牺牲现行高支路／间接火力弧形和越障特征，需要确认T语义改变；保持225m/s并只换“另一个高解”不可行，当前方程只有两支。
- **B只增时间约束**在不准改速度／分支时只能报不可达，不能解决体验；作为软偏好须配合新profile机制。
- **C只改TEST ONLY参数**没有对应45秒根因：临时瞄准／装填影响发射等待或下一发，不改变已发弹丸高弧；当前不存在可改的临时M252初速。
- **D改固定正式初速**也无法让全射程高抛都≤10秒：要保留1800米，同高程至少需约134.16m/s，近距高支路仍约26.8秒。若进一步降至≈50m/s则最大水平可达仅250米，牺牲正式射程。全局g保持10。

因此本轮没有选定或实施新的弹道设计，正式参数保持。10秒是用户体验目标，未被提升为绝对物理契约。

## E. Camera Before / After

|参数|Before|After（仅活动TEST ONLY）|
|---|---|---|
|camera distance min / max|6 / 60米|6 / 500米|
|max camera height，80°俯仰|59.09米|492.40米|
|max height，常用45°俯仰|42.43米|353.55米|
|min / max pan speed|18 / 18m/s|18 / 140m/s|
|400米平移，最大高度|22.22秒|2.86秒|
|keyboard pan rule|固定速度|t=clamp((D·sin(pitch)−h_min)/(h_max−h_min),0,1)，lerp(18,140,t)|
|zoom step|固定2米|每格max(2米,D×0.15)|
|edge-scroll / drag-pan|无|无|

h_min=6·sin20°≈2.05米，h_max=500·sin80°≈492.4米；中间D=250、pitch45°约61.5m/s。四角可见已离线验证，但实际可读性待人工。初始位置、ground height、pitch范围、旋转速度不变。独立resource_name清楚标TEST ONLY；数值是本轮明确允许的活动地图体验实现值，不是正式地图设计。建议先保留，人工评估140m/s／0.15滚轮比例是否过敏后再调整。

旧prototype_camera.tres内容不变，默认height_scaled_pan=false、zoom_distance_fraction=0；旧test_world及冻结Replay场景仍用旧资源，18m/s和2米缩放测试通过。MovementConfig和400×400米几何未改。

## F. Tests

证据tmp/db37-manual-recheck，以下均实际执行（SceneTree隔离测试，未启动真实客户端）：

|test name|pass count|fail count|
|---|---:|---:|
|projectile_history_clipping|36|0|
|active_camera|24|0|
|m252_flight_measurement|50|0|
|projectile_projection|42|0|
|projectile_render_separation|58|0|
|client_acceptance_fixes|93|0|
|db33_active_projectiles|60|0|
|db29_projectile|41|0|
|gravity_ballistics|50|0|
|projectile_unit_motion|43|0|
|prototype_05f|61|0|
|design_review|49|0|
|confirmed_game_data|55|0|
|prototype_02h|PASS，脚本未输出逐项计数|0|
|command_input|PASS，脚本未输出逐项计数|0|
|prototype_03a / 03b / 03c|各PASS，冻结v1兼容|0|

冻结03A/B/C覆盖读取、验证、round-trip、checkpoint/event边界与表现；未知版本拒绝保持。Editor import最终退出0、无Parse／SCRIPT ERROR；隔离日志证书环境ERROR与03B预期不支持录制拒绝分别核对，不作为测试失败。git diff --check通过，仅既有换行提示。正式JSON、Workbook、旧相机资源、活动movement与冻结v1文件SHA256与本轮开始相同。

## G. Remaining Manual Verification

- Projectile：两端分别观察0.5–1米近射、紧邻单位、近处地图碰撞／边界；中程、长程、多弹并行；观察全部0.12秒terminal余辉，确认不穿过发射位置向后延伸。
- M252：记录100、200、300米及当前地图最长有效测试距离的发射到落弹等待；可布置约500米对角线并记录T读数。400×400地图不能验收1800米，不把隔离扩展测量当真实客户端实测。
- Camera：最低高度精细操作、中空战术、最高高度全局、跨图速度／滚轮手感；四边及订单部署／战斗两阶段的焦点、点地／选兵操作。
- 实际客户端视觉、双端ENet／丢包抖动、远距离辨识和高空操作手感都未由自动测试证明；本轮未启动窗口或联网客户端，不宣称复验通过。

精确启停指令及当前待验项见[CLIENT_PROJECTILE_ACCEPTANCE.md](CLIENT_PROJECTILE_ACCEPTANCE.md)。

## H. Git Status

未commit、未push。工作区原有大量修改／删除／未跟踪文件以及本轮期间的文档目录迁移均保留，不清理或覆盖无关工作。实时git status的数量另在最终回复给出；本轮源码范围以上表为准。
