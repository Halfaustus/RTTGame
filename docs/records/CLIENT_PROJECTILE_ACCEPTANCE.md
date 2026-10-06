# 真实客户端弹丸验收

## 范围与当前证据

基线DB-2026-10-06-37。验收对象为Windows真实客户端经ENet接收弹丸公开投影、服务器时间同步和场景表现；不验收伤害／爆炸、完整战斗录制／播放或Replay v2，不把本次检查当作0.5大版本全部验收。

最新自动证据见[DB37_MANUAL_RECHECK.md](DB37_MANUAL_RECHECK.md)及tmp/db37-manual-recheck。用户本轮人工报告了近程尾迹越过炮口、M252等待过长及相机高度／速度不足。已修复历史裁剪和TEST ONLY活动相机；M252仅测量，正式高抛仍约44–45秒，需设计取舍后才能改变。修复后本清单仍待真实双端复验，不宣称人工通过。

## 启动：三个PowerShell终端

先关闭你自己此前运行的测试实例，确认UDP 7777空闲；不要结束不明进程。以下均为本机127.0.0.1，固定端口7777，不能同时开启另一组服务器。命令不带--record-replay。

终端1：启动独立无头服务器，并建立本次独立日志／停止令牌目录。保持该终端运行，看到Dedicated server started on port 7777后再开客户端。

```powershell
Set-Location C:\Projects\RTTGame
$acceptanceDir = Join-Path $PWD ("tmp\client-acceptance-" + (Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $acceptanceDir -ErrorAction Stop | Out-Null
$acceptanceDir | Set-Content -LiteralPath tmp\current-client-acceptance.txt -Encoding UTF8
$acceptanceToken = [guid]::NewGuid().ToString('N')
$acceptanceToken | Set-Content -LiteralPath (Join-Path $acceptanceDir token.txt) -Encoding ASCII
& C:\Dev\Godot\Godot_console.exe --headless --path C:\Projects\RTTGame\game --log-file "$acceptanceDir\server.log" -- --server "--shutdown-request=$acceptanceDir\shutdown.json" "--shutdown-token=$acceptanceToken"
```

终端2：启动客户端A。保留终端，游戏窗口可使用任务栏切换。

```powershell
Set-Location C:\Projects\RTTGame
$acceptanceDir = (Get-Content -LiteralPath tmp\current-client-acceptance.txt -Raw).Trim()
& C:\Dev\Godot\Godot_console.exe --path C:\Projects\RTTGame\game --resolution 1280x720 --position "20,40" --log-file "$acceptanceDir\client-a.log"
```

终端3：启动客户端B。两窗口需要看同一区域，可Alt+Tab切换；窗口位置可按显示器安排移动。

```powershell
Set-Location C:\Projects\RTTGame
$acceptanceDir = (Get-Content -LiteralPath tmp\current-client-acceptance.txt -Raw).Trim()
& C:\Dev\Godot\Godot_console.exe --path C:\Projects\RTTGame\game --resolution 1280x720 --position "160,100" --log-file "$acceptanceDir\client-b.log"
```

需要测指定渲染帧率时，在上述客户端命令的 --position 前加入 --max-fps 30（或60、120、144）；关闭对应窗口后重启，不调整服务器tick。上限不保证设备达到该FPS，可用视频／性能观察记录实际情况。

两端控制台应显示Connected to server及不同Local peer ID；购买面板显示账户余额。若服务器启动失败或客户端无法连接，先保留控制台错误和日志，不继续把弹丸不可见记为视觉失败。

## 操作与验收清单

鼠标左键／兵牌选择己方单位，右键移动；WASD平移相机，滚轮缩放，中键或Alt旋转。G后右键地面强制开火，T后右键地面为单点一发炮击。E第一次退出选点，退出后再E停止任务；Esc打开菜单而不取消选点。失去窗口焦点会退出选点，所以先在当前窗口完整下达命令，再切换观察。

购买面板中武装步兵对应test.rifle；迫击炮条目当前直接显示test.mortar。购买后左键放置暗化订单，等待3秒生成及行军完成；不要在仍拿着订单时按G／T。测试迫击炮正式射程100–1800米，当前400×400米地图只覆盖其中一部分。

|项目|操作|预期结果|实际状态|
|---|---|---|---|
|双客户端与权限|A、B各选择自己的出生班组，分别下移动命令；B尝试选择／指挥A的单位|两个不同玩家均连接；己方命令可执行，不能控制另一玩家的单位|待验收|
|直射公开轨迹|A选择停稳班组，G后右键约10–20米外无障碍地面；A、B相机看该处|两端可见独立长度的黄色渐隐轨迹，弹头较亮，尾部接近透明；不出现枪口到落点整段均匀亮线。900m/s配置上限主要亮段约10.8米，淡尾总长约21.6米；近距离按实际已知路径缩短，不延伸到炮口后方；B不必拥有射手。没有伤害／爆炸表现不算失败|待验收|
|极近距离与终止|分别向约0.5–1米近处、紧邻单位、近处障碍及边界射击，等待末段消失；两端观察|从第一显示帧到0.12秒余辉结束，尾部都不越过发射位置，不穿过班组向后延伸；零距离不造线|待复验|
|中长程／多弹|比较约50–100米及地图内长距离，重复发射并观察多条轨迹|达到视觉长度上限后不继续增长，尾部渐隐；各弹独立、不混用历史|待复验|
|G一次性与取消|A用G向地面下令一次，持续观察3秒并移动；重新G后在发射前马上移动|各有资格的武器通道仅实际发射一次，不持续开火；移动取消未发射任务，已发弹丸仍终止。混合班组可能有多个通道同时各打一发|待复验|
|相对归属颜色|A、B各生成己方单位并互看；检查兵牌、模型及己方暗化订单|A自己的单位蓝色、B的单位绿色；B自己的单位蓝色、A的单位绿色；订单仍暗化|待复验|
|两端旋转|分别切入A、B；在地图空白及兵牌处按住Alt移动鼠标，再独立按住中键移动；两键同时按住后分别松开；Alt+Tab回来重试|两端都可转动，相机捕获不被兵牌悬停取消；最后一个激活键松开停止，切窗后不残留捕获。购买／文本控件仍正常接收输入|待复验|
|炮击预览与距离|A选择停稳炮组，T选点并移动鼠标；B观察同一区域；试小于100米和合法范围|仅A显示红色实线名义高抛弹道与火炮位置到选点的米数；无效范围显示原因；B不显示A预览。距离持续更新，退出T／失焦后清除，未确认不发射、不扣弹|待复验|
|插值连续性|两端分别限制30／60／120／144FPS观察较长飞行炮弹；必要时记录慢动作视频|客户端逐渲染帧连续移动，不按30Hz重复停顿跳跃；FPS只改变平滑程度，不产生更长亮线。当前没有专门帧率设置面板，设备无法达到的档位记录未验证|待验收|
|迫击炮高抛|A购买test.mortar并在初始区域附近部署，等待停稳；选中炮组，用T预览距离读数确认落点在100米以上，再右键地面；两端看相同落点|服务器接受T，约45秒后两端看到末段下降／地面终止；不是低平直线秒到。不要求相机始终看见高空弹丸|待验收|
|任务完成不清飞行|上一步下令后切回炮组区域，E退出交互，再E停止或右键移动炮组；两端回落点观察|已经发出的炮弹仍落下；停止／移动不会取消飞行，也不额外重复开火|待验收|
|晚加入同步|先让A、B在同一明显地标附近选定合法落点并记住位置，关闭B窗口。A再向该点发一枚T炮弹，约30秒后在终端3重新执行客户端B命令；B缩放到高视角找到该地标，再移到落点区域观察到落地，不用固定W持续时间估算位置|B加入后接收仍飞行弹丸，末段及终止与A一致，不从炮口重新播放，也不出现重复弹丸。若未在同一区域观察到，记为待复测，不能直接判同步通过／失败|待验收|
|短程同批终止|A用班组G攻击近处地面，B看同一点|同一服务器步内结束的弹丸仍有短暂黄色末段显示，之后清除，不出现长时间悬空线|待验收|
|失视不限制公开投影|不需要点亮敌人；观察另一玩家已发出的弹丸，并移开／移回相机|弹丸不因本地选择／相机离开消失；不因看到轨迹而出现额外敌方兵牌或实时单位状态。真正敌方隐藏射手发射当前无可操作测试入口，此子项保留未验证|部分可测，其余未验证|
|边界与交互|WASD到地图边缘；选T后Esc、返回游戏，再E；选T后切换窗口再回来|相机地面焦点不越界；Esc保留选点，E退出；焦点丢失清选点，不误下令|待验收|
|M252距离与节奏|分别测试100、200、300米及当前地图能布置的最长有效距离（可尝试约500米对角线），记录T读数、发射至落地等待、遮挡情况|当前正式高抛仍约44–45秒；1800米不能在400×400米地图实测，不提前显示爆炸或将客户端飞行压成10秒|待人工记录|
|相机高度与速度|在最低／中间／最高高度选兵和点地，跨图移动；检查四个焦点边界，并在订单部署和战斗阶段重复|低空细调、中空战术、高空看到整体；最高实际高度约492米，高空400米移动约2.9秒。焦点留在地图内，部署与地面坐标正确；旧地图保持原设置|待复验|
|断线清理|保持A打开，按下节正常停止服务器|两端提示连接结束，弹丸／末段表现和购买状态清理；不残留继续飞行的轨迹|待验收|
|稳定性与错误|保持双端运行约3分钟，重复几次G／T，检查日志|无崩溃、SCRIPT ERROR、RPC参数错误或明显持续残影；观察帧率／卡顿但不据短测宣称长期性能通过|待验收|

迫击炮高抛顶点远高于地面相机视域，过程飞出画面是正常现象。黄色线半宽0.035米、终止余辉0.12秒及视觉时间窗口0.012秒均为当前临时表现值；若过细或太短难以辨认，报告视觉可读性问题，不把“没有看到”直接等同服务器没有发射。100米内炮击会被拒绝，服务器控制台出现Artillery accepted才说明命令被接受；接受也不能单独证明已经发射或完成显示。

没有地图坐标显示；当前T预览显示实际武器位置到选点的距离，应以该读数确认不低于100米。活动地图相机速度现在随高度变化，不再用固定W持续时间估算距离。测试不能由屏幕直接验证所有身份／隐私字段，也未覆盖真实敌方隐藏射手、延迟／丢包、Linux或长期压力；这些与已通过的离线契约测试分开记录。

## 正常停止与证据

先保持客户端窗口打开，以验证断线清理。终端4发起正常服务器停止（不按进程名强制结束）：

```powershell
Set-Location C:\Projects\RTTGame
$acceptanceDir = (Get-Content -LiteralPath tmp\current-client-acceptance.txt -Raw).Trim()
$acceptanceToken = (Get-Content -LiteralPath (Join-Path $acceptanceDir token.txt) -Raw).Trim()
@{ action = 'finish'; token = $acceptanceToken } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $acceptanceDir shutdown.json) -Encoding ASCII
```

等待服务器终端打印SERVER normal shutdown: recording=disabled; exit=0并返回提示符；随后读取收据：

```powershell
Get-Content -LiteralPath (Join-Path $acceptanceDir shutdown.json.receipt.json)
```

应有normal_shutdown:true、exit_code:0，recording状态disabled。确认客户端清理后，使用游戏窗口右上角×关闭A和B；客户端终端返回提示符。若服务器没有正常退出，保留错误后只在该服务器前台终端Ctrl+C中断，不结束其他Godot进程；这种中断不能记作正常停止通过。

读取本轮日志及错误索引：

```powershell
Get-Content -LiteralPath (Join-Path $acceptanceDir server.log) -Tail 40
Get-Content -LiteralPath (Join-Path $acceptanceDir client-a.log) -Tail 40
Get-Content -LiteralPath (Join-Path $acceptanceDir client-b.log) -Tail 40
Select-String -Path "$acceptanceDir\*.log" -Pattern 'SCRIPT ERROR|ERROR:|RPC|Disconnected|Connected|Artillery|Ground Fire'
```

重启B会再次使用client-b.log，Godot可能轮转旧日志；需要保留首次B观察证据时，在重启前复制日志或另设client-b-late.log。请反馈每项通过／失败／未验证；失败附A或B、操作、预期、实际现象、时间及相关日志。可附截图／视频判断两端效果。不要仅凭没有报错或自动测试通过将本清单全部标为通过。
