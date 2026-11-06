# TSNsched 二次开发交接文档

> 交接日期：2026-11-06 ｜ 交接目标：在另一台本地 Linux 环境继续开发
> 原仓库：`https://github.com/Zhang-Jia/TSNsched`（fork，GPL v3）

---

## 1. 本次工作概况

在云端沙箱（Ubuntu 24.04，`/workspace` = TSNsched 仓库根目录）完成了四项新工作，**未改动原仓库任何源码**，新增文件均为独立产物：

| # | 产物 | 位置 | 说明 |
| --- | --- | --- | --- |
| 1 | **TSN Studio Web GUI** | `tsn-web-gui/index.html`（65 KB / 1183 行，单文件零依赖） | 拖拽拓扑编辑器 + 流量配置 + 内置贪心调度仿真 + 三类配置导出 |
| 2 | **Code Wiki 文档** | `CodeWiki.md`（33 KB） | 原仓库全源码结构化文档：架构/模块/类函数/依赖/运行方式 |
| 3 | **Win11 免安装包** | `tsn-studio-win11.zip`（21 KB） | GUI + `run.bat`，解压双击即用 |
| 4 | **Linux 一键部署脚本** | `dist/deploy-tsn.sh`（94 KB） | 内嵌 GUI + 演示拓扑 + 后端入口；自动装依赖→编译→Z3 求解→起 Web 服务 |

另完成**后端联通实测**（非文件产出）：GUI 导出格式的 JSON 在真实 Z3 后端求解成功，并定位了两个后端兼容性坑（见第 5 节）。

> ⚠️ 沙箱是临时的，所有文件**必须先下载转移到你的开发机**（见第 8 节）。

---

## 2. 目标开发机环境（已验证可用组合）

| 组件 | 版本 | 安装方式 | 备注 |
| --- | --- | --- | --- |
| OS | Ubuntu 22.04 / 24.04（apt 系） | — | 其他发行版需自行对应包名 |
| JDK | OpenJDK 17（沙箱用 Java 25 也跑通） | `sudo apt install openjdk-17-jdk` | 官方 README 写 JDK8，但实测高版本兼容 |
| Z3 Java 绑定 | **4.8.12**（`libz3-java`） | `sudo apt install libz3-java` | **不要用仓库自带 z3 jar**，原因见第 5 节坑① |
| Python3 | 任意 | 系统自带 | 仅用于 GUI 静态服务 |
| 浏览器 | Chrome / Edge | — | GUI 运行环境 |

关键路径（apt 安装后）：
- Z3 jar：`/usr/share/java/com.microsoft.z3.jar`
- Z3 原生库：`/usr/lib/x86_64-linux-gnu/jni`（运行时用 `-Djava.library.path` 指定）

---

## 3. 快速部署（二选一）

### 方式 A：一键脚本（推荐）

```bash
bash deploy-tsn.sh                 # 机器上无仓库时自动 git clone
bash deploy-tsn.sh /path/to/TSNsched   # 机器上已有仓库时指定路径
```

脚本执行后：GUI 在 `~/tsn-studio/web/`，后端在 `~/tsn-studio/backend/`，Web 服务监听 `8137`。
如启防火墙：`sudo ufw allow 8137`。

### 方式 B：手动（理解用，脚本即这些命令的封装）

```bash
sudo apt update && sudo apt install -y openjdk-17-jdk libz3-java python3

# 编译 + 运行后端（$REPO = TSNsched 仓库根目录，$LIBS = $REPO/Script/libs）
javac -d . -classpath "/usr/share/java/com.microsoft.z3.jar:$LIBS/gson-2.8.6.jar:$LIBS/java-json.jar:$LIBS/TSNsched.jar" RunDemo.java
java -Djava.library.path=/usr/lib/x86_64-linux-gnu/jni \
     -classpath ".:/usr/share/java/com.microsoft.z3.jar:$LIBS/gson-2.8.6.jar:$LIBS/java-json.jar:$LIBS/TSNsched.jar" \
     RunDemo demo.json        # 成功后生成 output.json

# 启动 GUI
cd tsn-web-gui && python3 -m http.server 8137   # 访问 http://<IP>:8137/index.html
```

后端入口类逻辑（10 行）：`new JSONParser(file).parseInput()` → `new ScheduleGenerator().generateSchedule(net)` → `parser.generateOutput(net)`。参考仓库自带 `Script/GenerateScheduleJSONInput.java`。

---

## 4. 验证基线（环境搭好后跑这套回归）

**演示拓扑**（GUI「载入示例」/ 脚本内嵌 `demo.json`）：2 交换机（SW1/SW2，125 B/µs=1Gbps，保护带 10µs）+ 5 端设备 + 3 条流（control: PLC1→CTRL1 周期 500µs；video: CAM1→HMI1 3000B/1000µs；telemetry: SENSOR1→HMI1 1000µs）。周期 T=500µs，超周期 HP=1000µs。

| 检查项 | 期望结果 |
| --- | --- |
| Z3 后端求解 demo.json | SAT；control 平均延迟 **25.04µs**、video **74.0µs**、telemetry **38.0µs**，抖动均为 0 |
| GUI 内置贪心调度 | 最差端到端 **75.0µs**、违规 0、TT 时隙 6 个、最高端口利用率 5.6% |
| GUI 冒烟 | 载入示例 → 7 节点 6 链路 → 生成调度 → 甘特图 3 行 + 流表 3 行全绿「满足」；拖动节点无残影；控制台无红错 |

---

## 5. 已踩坑与规避（续开发前必读）

1. **Z3 jar 版本不匹配**：仓库 `libs/com.microsoft.z3.jar`（4.8.0）与 `TSNsched.jar` 编译目标版本不一致，运行报 `NoSuchMethodError: void com.microsoft.z3.Solver.add(com.microsoft.z3.Expr[])`。**解法**：classpath 用 apt 的 4.8.12 jar，排除仓库自带 z3 jar（gson/java-json 仍用仓库的）。
2. **同源设备多条流 → Z3 UNSAT**：后端模型中同一 Device 发出的多条流共享发送流，拓扑本身可调度也会 UNSAT。**规避**：每个发送端只规划一条流，或放大周期。GUI 内置贪心调度不受此限。
3. **JSON 解析器无视 `type` 字段**：所有 JSON 流一律按 `PUBLISH_SUBSCRIBE` 解析（单终点时内部转单播树），`"type":"unicast"` 写了也没用（`JSONParser.getListOfFlows`）。
4. **后端流参数取自设备默认值**：周期/报文大小/硬约束读的是 Device 的 `default*`，Flow 级参数仅 GUI 仿真使用。
5. **GUI 拖影 bug（已修）**：全局复用的 `gLinks/gNodes` SVG 分组跨重绘累积子元素导致残影，修复方式为重绘前 `innerHTML=''`。若另存过旧版 index.html 请注意替换。
6. **后台进程存活**：某些容器/终端环境 `nohup ... &` 会被清理，GUI 服务建议用 `tmux`/`systemd` 托管。

---

## 6. GUI 代码结构导览（`tsn-web-gui/index.html`）

单文件，无构建步骤，改完刷新浏览器即生效。JS 按注释分节：

| 区段 | 关键内容 |
| --- | --- |
| `State` | 全局 `state`：`nodes/links/flows/settings/sel/view/schedule`；节点含 `portSpeed/gb`（交换机）或 `packetSize/period/firstT1/hardConstraint`（设备） |
| `Scheduler` | `generateSchedule()`：BFS 路由 → LCM 超周期 → 按(优先级,截止期)排序逐包分配；`findSlot()` 端口时隙冲突检测；`buildGcl()` 生成门控表（含保护带、尽力而为间隙） |
| `Exports` | `exportTsnJson()`（后端兼容 JSON）、`exportNetconfXml()`（TrustNode YANG 的 GCL）、`exportResultsJson()` |
| `Canvas` | `renderCanvas()/renderNode()/renderLink()`：SVG 全量重绘 + 平移缩放；交互：拖拽/连线/删除三模式 |
| `Demo` | `loadDemo()`：第 4 节的演示拓扑，改示例就改这里 |

**扩展指引**：
- 新调度算法：替换 `generateSchedule()`，保持输出结构 `state.schedule = {T, HP, ports[{sw,nb,portNum,slots,gcl,util}], results[]}` 不变，下游甘特图/导出无需改动。
- 接 REST 后端：在 `generateSchedule` 处改为 `fetch(后端URL, {body: 导出的TSNsched JSON})`，把返回的 `output.json` 映射进 `state.schedule.results`。
- 新导出格式：仿照 `exportNetconfXml()` 遍历 `state.schedule.ports[].gcl` 即可。

---

## 7. 后端接口要点

**输入 JSON schema**（`JSONParser` 实际读取的字段）：

```jsonc
{
  "switches": [{ "name", "scheduleType":"hypercycle", "defaultTimeToTravel", "defaultPortSpeed", "defaultGuardBandSize",
    "ports": [{ "name", "connectsTo", "timeToTravel", "portSpeed", "guardBandSize", "scheduleType":"microcycle", "maximumSlotDuration", "cycleStart" }] }],
  "devices": [{ "name", "defaultFirstSendingTime", "defaultPacketPeriodicity", "defaultHardConstraintTime", "defaultPacketSize" }],
  "flows":   [{ "name", "type", "sourceDevice", "endDevices":["..."], "hops":[{"currentNodeName","nextNodeName"}] }]
}
```

**NetConf XML**：根 `<nc:config xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0">` → `<TNtas xmlns="urn:sysrepo:TrustNode:TNsysrepo">` → `<ports>` 含 `<id>`/`<GCL><id><timeperiod><gatestates>`/`admin_base_time`/`gate_enable`。门状态为位掩码 `2^队列号`，保护带为 0，间隙为 1（Q0）。YANG 模型目前**硬编码 TrustNode**，对接其他厂商需改 `XMLExporter.java` 的常量与标签（或导出层做适配器）。

**`output.json`**：`flows[]`（averageLatency/jitter/firstSendingTime/hops+priority）+ `switches[]`（端口 cycle 信息）。

---

## 8. 文件转移到新开发机

沙箱内下载（聊天界面直接下载），再拷到开发机：

```bash
# 在 Win11/本机下载后（示例）
scp deploy-tsn.sh tsn-studio-win11.zip CodeWiki.md HANDOVER.md mrchaos@<开发机IP>:~/
# 开发机上
bash ~/deploy-tsn.sh /path/to/TSNsched
```

也可以把 `tsn-web-gui/`、`dist/`、`CodeWiki.md`、`HANDOVER.md` 直接提交到你的 fork（均在仓库根目录，不与原源码冲突）：

```bash
git add tsn-web-gui dist CodeWiki.md HANDOVER.md && git commit -m "feat: add TSN Studio web GUI, deploy script and docs"
```

---

## 9. 后续开发路线建议（按优先级）

1. **后端 REST 化**：Spring Boot 薄封装 `generateSchedule`（JSON 进/出），GUI 加「真实求解」按钮替换内置贪心——架构上与 GPL 引擎形成进程隔离（商用合规，见 CodeWiki 方案讨论）。
2. **YANG 适配层**：`XMLExporter` 的 TrustNode 硬编码改为可插拔，支持 `ieee802-dot1q-sched` 标准模型。
3. **仿真导出升级**：`nest_sched`（NeSTiNg，已停更）→ INET 4.3+ 原生 TSN（Qbv/Qci/CB）。
4. **工程化**：求解超时/大拓扑回退策略、JUnit + GUI e2e 测试、i18n。

---

## 10. 联系上下文

- 架构决策（为什么选「闭源平台 + GPL 引擎服务」路线）、NetConf 下发实物流程、Win11/WSL2 环境结论：见会话记录与 `CodeWiki.md` 第 9 章。
- GUI 帮助弹窗内含用户使用说明与后端兼容性注意事项，可直接作为用户文档底稿。
