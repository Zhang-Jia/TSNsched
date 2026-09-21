# TSNsched 项目代码 Wiki

> TSNsched 使用 [Z3 定理证明器](https://github.com/Z3Prover/z3) 为**时间敏感网络（Time Sensitive Networking, TSN）**自动生成流量调度表。该项目是 fortiss 与巴西帕拉伊巴联邦大学（UFPB）合作研究的成果，基于 IEEE 802.1Qbv（时间感知整形器 / Time-Aware Shaper）思想实现，授权协议为 GNU GPL v3 或更高版本。

- 理论基础论文：*TSNsched: Automated Schedule Generation for Time Sensitive Networking*（FMCAD 2019）
- 硕士论文：*TSNsched: Automated Schedule Generation for Time Sensitive Networking*（M.Sc Dissertation 2020）

---

## 目录

1. [项目概述](#1-项目概述)
2. [整体架构](#2-整体架构)
3. [技术栈与依赖](#3-技术栈与依赖)
4. [目录结构](#4-目录结构)
5. [主要模块职责](#5-主要模块职责)
6. [关键类与函数说明](#6-关键类与函数说明)
7. [核心调度流程](#7-核心调度流程)
8. [输入与输出格式](#8-输入与输出格式)
9. [项目运行方式](#9-项目运行方式)

---

## 1. 项目概述

TSNsched 将「为一组 TSN 流生成可行的门控调度表」建模为一个**约束满足问题（SMT）**，交由 Z3 求解。核心思想如下：

- **拓扑**：由设备（`Device`，即发送方/接收方）、TSN 交换机（`TSNSwitch`）以及连接它们的端口（`Port`）组成。
- **流（Flow）**：表示从单个源到单个/多个目的地的数据流，支持两种类型——**单播（Unicast）** 和 **发布-订阅（Publish-Subscribe）**。
- **调度**：每个交换机端口拥有一个循环周期（`Cycle`），周期内划分出优先级时隙（slot），流量被拆分为「流片段（FlowFragment）」，在 Z3 中为出发时间、到达时间、调度时间、时隙起止、优先级等建立约束，一次性求解得到满足所有约束（延迟硬约束、抖动上界、无冲突等）的调度结果。

输出包括：调度日志（`log.txt`）、JSON 输出（`output.json`）、NetConf 门控列表 XML、以及用于 NeSTiNg / OMNeT++ / INET 仿真的 `.ned`、`.ini`、`.xml` 文件。

---

## 2. 整体架构

TSNsched 采用分层、模块化的 Java 设计。各层之间通过 `Network` 这一中心数据结构贯通数据流。

```
┌─────────────────────────────────────────────────────────────────┐
│                         入口层 (Entry)                            │
│   com.tsnsched.core.Main                                         │
│   Script/GenerateScheduleJavaInput  Script/GenerateScheduleJSONInput│
└──────────────────────────────┬──────────────────────────────────┘
                               │ 调用
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    接口管理 (interface_manager)                   │
│   GenericParser(接口) ── JSONParser ── XMLParser ── ParserManager │
│   Printer(日志/输出)  SizeUnits  TimeUnits                        │
│   职责：解析输入 JSON/XML → Network；输出日志/JSON                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │ 产出 Network
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    网络数据模型 (network / components / nodes)      │
│   Network ── Switch ── TSNSwitch ── Port ── Cycle                │
│   Flow ── FlowFragment ── PathNode ── PathTree ── Device         │
│   职责：描述拓扑、流、端口、周期等；承载 Z3 变量                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │ 交给调度器
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   调度生成 (schedule_generator)                   │
│   ScheduleGenerator  ScheduleType  SlotArrangementMode           │
│   职责：建 Z3 上下文与求解器 → 施加约束 → solver.check() → 取值   │
└──────────────┬───────────────────────────────┬──────────────────┘
               │                               │
               ▼                               ▼
┌──────────────────────────┐   ┌──────────────────────────────────┐
│  sched2netconf            │   │  nest_sched (NeSTiNg 仿真文件生成) │
│  XMLExporter / Triple     │   │  NestSchedXMLGen / NEDGen / INIGen│
│  输出 NetConf 门控列表 XML │   │  NestSchedAux                     │
└──────────────────────────┘   └──────────────────────────────────┘
```

**数据流主线**：`输入文件（JSON/XML/Java）` → `Network 对象（拓扑+流）` → `ScheduleGenerator.generateSchedule(net)` → `Z3 求解` → `Printer 写日志 / XMLExporter 写 NetConf / NestSched* 写仿真文件 / JSONParser 写 output.json`。

---

## 3. 技术栈与依赖

| 依赖 | 用途 | 位置 |
| --- | --- | --- |
| Java 1.8.0_181（JDK 8） | 主要实现语言 | — |
| Z3 4.8.0.0（`com.microsoft.z3.jar`） | SMT 定理证明求解器 | `libs/` |
| Gson 2.8.6（`gson-2.8.6.jar`） | JSON 解析（输入） | `libs/` |
| `java-json.jar` | JSON/XML 互转（`org.json`） | `libs/` |
| TSNsched（`TSNsched.jar`） | 本项目自身打包产物 | `libs/` |

- 构建/工程文件：`.classpath`、`.project`（Eclipse 工程）、`install-dependencies.sh`（依赖安装脚本）、`Script/generateSchedule.sh`（命令行运行脚本）。
- 可选运行环境：NeSTiNg（TSN 仿真模型）+ OMNeT++ 5.5.1 + INET 4.1.2（用于仿真验证）。

`.classpath` 中声明的第三方库（`src` 为源码目录，`bin` 为输出目录）：

```xml
<classpathentry kind="src" path="src"/>
<classpathentry kind="lib" path="libs/com.microsoft.z3.jar"/>
<classpathentry kind="lib" path="libs/java-json.jar"/>
<classpathentry kind="lib" path="libs/gson-2.8.6.jar"/>
<classpathentry kind="output" path="bin"/>
```

---

## 4. 目录结构

```
/workspace
├── src/com/tsnsched/
│   ├── core/                       # 核心调度逻辑
│   │   ├── Main.java               # 程序入口
│   │   ├── components/             # 核心数据组件
│   │   │   ├── Cycle.java          # TSN 周期与时隙
│   │   │   ├── Flow.java           # 流（单播/发布订阅）
│   │   │   ├── FlowFragment.java   # 流片段（单跳）
│   │   │   ├── PathNode.java       # 路径树节点
│   │   │   ├── PathTree.java       # 路径树
│   │   │   └── Port.java           # 交换机端口（调度核心）
│   │   ├── nodes/                  # 网络节点
│   │   │   ├── Device.java         # 发送/接收设备
│   │   │   ├── Switch.java         # 普通交换机（基类）
│   │   │   └── TSNSwitch.java      # TSN 交换机
│   │   ├── network/
│   │   │   └── Network.java        # 网络拓扑
│   │   ├── schedule_generator/
│   │   │   ├── ScheduleGenerator.java # 调度生成器（Z3 求解）
│   │   │   ├── ScheduleType.java      # 调度类型枚举
│   │   │   └── SlotArrangementMode.java # 时隙排列模式枚举
│   │   ├── interface_manager/      # 输入输出接口
│   │   │   ├── GenericParser.java  # 解析器接口
│   │   │   ├── JSONParser.java     # JSON 解析
│   │   │   ├── XMLParser.java      # XML 解析
│   │   │   ├── ParserManager.java  # 解析器调度
│   │   │   ├── Printer.java        # 日志/输出
│   │   │   ├── SizeUnits.java      # 数据量单位
│   │   │   └── TimeUnits.java      # 时间单位
│   │   └── sched2netconf/
│   │       ├── XMLExporter.java    # NetConf XML 导出
│   │       └── Triple.java         # (队列,起始,时长) 元组
│   ├── nest_sched/                 # NeSTiNg 仿真文件生成
│   │   ├── NestSchedAux.java
│   │   ├── NestSchedINIGen.java
│   │   ├── NestSchedNEDGen.java
│   │   └── NestSchedXMLGen.java
│   └── generated_scenarios/        # 内置示例场景
│       ├── SmallScenario.java
│       ├── GeneratedCode.java
│       ├── input.json / input.xml
├── Script/                         # 命令行运行脚本与用例
│   ├── generateSchedule.sh         # 运行脚本
│   ├── example.java                # 示例拓扑
│   ├── GenerateScheduleJavaInput.java
│   ├── GenerateScheduleJSONInput.java
│   └── libs/                       # 依赖 jar
├── ScenarioGenerator/              # 拓扑生成器
│   └── ScenarioGenerator.java
├── TestCases/                      # 论文测试用例
├── XMLExporterFiles/               # XMLExporter 默认输出目录
├── nestSched/                      # NeSTiNg 仿真输出目录
├── libs/                           # 依赖 jar（根级）
├── Academic work/                  # 论文 PDF
├── README.md / FAQ.md / src/README.md
└── install-dependencies.sh         # 依赖安装脚本
```

---

## 5. 主要模块职责

| 包 / 模块 | 职责 |
| --- | --- |
| `core` | 程序入口 `Main`，根据命令行参数选择运行方式 |
| `components` | 定义流的表示（`Flow`、`FlowFragment`）、路径结构（`PathTree`、`PathNode`）、周期与时隙（`Cycle`）、端口调度（`Port`） |
| `nodes` | 定义网络节点：`Device`（端设备）、`Switch`（基类）、`TSNSwitch`（TSN 能力交换机） |
| `network` | `Network` 聚合拓扑（设备+交换机+流），并实现硬约束/抖动约束/首跳防冲突等整体约束 |
| `schedule_generator` | `ScheduleGenerator` 创建 Z3 上下文与求解器，编排全流程；两个枚举定义调度类型与时隙排列模式 |
| `interface_manager` | 输入解析（JSON/XML）、输出（日志/JSON）、单位换算、日志打印 |
| `sched2netconf` | 把调度结果导出为 NetConf 门控列表（GCL）XML |
| `nest_sched` | 把调度结果转译为 NeSTiNg 仿真所需的 `.ned`、`.ini`、`.xml` 文件 |
| `generated_scenarios` | 内置示例网络（`SmallScenario` 三流单播、`GeneratedCode` 大拓扑） |

---

## 6. 关键类与函数说明

### 6.1 节点层（`nodes` 包）

#### `Device`（端设备）
表示流的起点或终点，其属性构成流约束的核心。

- 属性：`name`、`packetPeriodicity`（发包周期）、`firstT1Time`（首包发送时间）、`hardConstraintTime`（最大容忍延迟/硬约束）、`softConstraintTime`（软约束）、`packetSize`（包大小）。
- 关键方法：
  - `toZ3(Context ctx)`：把数值属性转成 Z3 变量（`firstT1TimeZ3` 为待求解的 `RealConst`，其余为常量）。
  - 构造函数重载支持 `double` 与 `RealExpr`（Z3）两种传参。
  - 大量 getter/setter 提供数值与 Z3 双版本。

#### `Switch`（普通交换机基类）
持有构建调度所需的普通交换机属性，暂不含 Z3 属性（未来可扩展）。

- 属性：`name`、`maxPacketSize`、`timeToTravel`、`transmissionTime`、`portSpeed`。
- 说明：当前作为 `TSNSwitch` 的父类，未参与普通交换机与 TSN 交换机混合场景。

#### `TSNSwitch`（TSN 交换机，继承 `Switch`）
描述具备 TSN 能力的交换机，组织与其它节点相连的端口序列。

- 属性：`ports`、`connectsTo`（可达节点名列表）、`gbSize`（保护带大小）、`cycleDurationLowerBound/UpperBound`、`scheduleType`。
- 关键方法：
  - `createPort(Object/Destination 名, Cycle)`：创建端口并关联周期，根据 `scheduleType` 设置微周期/超周期。
  - `addToFragmentList(FlowFragment)`：按下一跳定位端口，把流片段加入对应端口的片段列表。
  - `getPortOf(String name)`：按节点名查找对应端口。
  - `toZ3(Context, Solver)`：创建周期时长/起始 Z3 变量，施加周期时长上下界、周期起始非负等约束，并统一所有交换机周期起始为 0。
  - `setupSchedulingRules(Solver, Context)`：遍历端口，逐个建立调度规则。
  - `setUpCycleSize(Solver, Context)`：为启用自动化应用周期的端口计算周期大小。
  - `arrivalTime / departureTime / scheduledTime(...)`：检索指定流片段、指定包的到/发/调度时间的 Z3 表达式。

### 6.2 组件层（`components` 包）

#### `Cycle`（TSN 周期与时隙）
表示 TSN 交换机的周期——一个指定时长的时间区间，内部按约束分布时间窗（时隙），窗口内对应优先级队列的闸门打开。

- 属性：`upperBoundCycleTime`、`lowerBoundCycleTime`、`firstCycleStart`、`maximumSlotDuration`、`cycleDuration`、`cycleStart`、`numOfPrts`（默认 8）、`slotArrangementMode`。
- 关键方法：
  - `toZ3(Context)`：创建周期时长/起始 Z3 变量，按 `numOfPrts × numOfSlots` 生成时隙起止 Z3 变量矩阵。
  - `cycleStartZ3(Context, ...)`：返回第 index 个周期的起始时间（`firstCycleStart + duration * index`）。
  - `setNumOfSlots(int)`：按 `SlotArrangementMode` 分配各优先级时隙数。
  - `addSlotUsed(prt, start, duration)` / `getSlotStart` / `getSlotDuration`：求解后回填已用时隙的起止。
  - `loadZ3(Context, Solver)`：反序列化后重建 Z3 约束。
- **重要设计说明**（源自源码注释）：`Cycle` 与其时隙之间没有直接引用。用户必须通过「流片段（flow fragment）的优先级」来索引某个时隙。这是因为 Z3 变量按 `cycleXSlotflowNfragmentMpriorityDuration` 命名，而非 `cycleXSlot3Duration`。因此，属于同一时间窗的流具有相同优先级，且优先级取值上限为槽位数，从而规避未用优先级带来的保护带问题。

#### `Flow`（流）
描述从一个源到单个/多个目的地的数据包流，包含路径、时序、包属性等全部数据。类型由静态常量区分：`UNICAST = 0`，`PUBLISH_SUBSCRIBE = 1`。

- 属性：`type`、`name`、`path`（单播，`ArrayList<Switch>`）、`flowFragments`、`pathTree`（发布订阅）、`startDevice`、`endDeviceList`、`packetSize`、`flowFirstSendingTime`、`flowSendingPeriodicity`、`flowMaximumJitter`、`flowMaximumLatency`、`fixedPriority`、`priorityValue`。
- 关键方法：
  - `addToPath(TSNSwitch)`（单播）/ `addToPath(Object source, Object destination)`（发布订阅）：构建路径。
  - `convertUnicastFlow()`：将单播流转换为无分支的发布订阅结构，统一内部表示。
  - `toZ3(Context)`：将流属性转为 Z3，并根据类型分别调用 `pathToZ3`（单播）或 `nodeToZ3`（发布订阅）生成流片段。
  - `nodeToZ3(Context, PathNode, FlowFragment)`（递归）：遍历路径树，为每对「节点→子节点」创建 `FlowFragment`，设置下一跳、首片段的出发时间（=源设备首发送时间 + 周期×索引）或后续片段的出发时间（=前一节点调度时间），并注册到端口。
  - `pathToZ3(...)`：单播流的逐跳片段生成。
  - `bindToNextFragment / bindAllFragments`：串联相邻片段（上一跳调度时间 = 下一跳出发时间）。
  - `assertFirstSendingTime(Solver, Context)`：约束流首发送时间（确保首包能完整发出，且落在首跳周期内）。
  - `setUpPeriods(PathNode)`：把流的周期登记到沿途端口，用于自动化应用周期。
  - `getDepartureTime / getArrivalTime / getScheduledTime`（单播按 hop，发布订阅按目标设备 Device 或名称）：读取求解后的包时间。
  - `getAverageLatency / getAverageJitter`：计算平均延迟/平均抖动。

#### `FlowFragment`（流片段，继承 `Flow`）
表示流在某个交换机的「单跳片段」，是流的原子化拆分——一条流不管类型如何，都拆成片段分发到各交换机。

- 属性：`parent`（所属流）、`port`、`referenceToNode`、`fragmentPriority`、`nodeName`（当前节点）、`nextHopName`（下一跳）、`numOfPacketsSent`、`previousFragment`、`nextFragments`、以及到/发/调度时间的数值列表与 Z3 表达式列表。
- 关键方法：`addDepartureTimeZ3 / getDepartureTimeZ3`、`addScheduledTimeZ3 / getScheduledTimeZ3`、`getFragmentPriorityZ3 / setFragmentPriorityZ3`、`getPreviousFragment / getNextFragments / addToNextFragments`、`setPort / getPort`。
- 说明：到/发/调度时间的数值是 `float` 而非 Z3 变量，Z3 变量通过 `Port`/`Switch` 获取。

#### `Port`（交换机端口 —— 调度核心）
实现交换机端口的调度逻辑，是整个调度过程的核心。其它类负责创建、管理和拆分流；端口汇集经过自身的流片段，从而专注解决「同一端口上的冲突」问题。

- 关键方法（含主要流程）：
  - `toZ3(Context)`：生成端口/周期的 Z3 变量。
  - `setupSchedulingRules(Solver, Context)`：调度主入口，依次调用 `setUpCycleRules`、`bindTimeSlots`、`zeroOutNonUsedSlots`，再对每个 `FlowFragment` 调用 `setupTimeSlots`、`setupDevPacketTimes`。
  - `setUpCycleRules`：建立周期相关约束。
  - `bindTimeSlots`：绑定流片段优先级与时隙。
  - `zeroOutNonUsedSlots`：把未使用时隙置零。
  - `setupTimeSlots(Solver, Context, FlowFragment)`：为单个流片段设置时隙约束。
  - `setupDevPacketTimes(Solver, Context, FlowFragment)`：设置包时间（到/发/调度）。
  - `setUpMicroCycles / setUpHyperCycle / setupBestEffort`：微周期/超周期/尽力而为的周期设置。
  - `setUpCycle(Solver, Context)`：自动化应用周期的周期大小计算。
  - `departureTime / arrivalTime / scheduledTime(...)`：检索到/发/调度时间的 Z3 表达式。
  - `getCycleOfScheduledTime / getCycleOfTime / getScheduledTimeOfPreviousPacket`：计算包所处周期索引、上一包调度时间等。
  - `loadZ3(Context, Solver)`：反序列化后重建 Z3 约束。
  - 大量 getter/setter：`getName`、`getConnectsTo`、`getPortSpeed`、`getFlowFragments`、`getListOfPeriods`、`getUseMicroCycles`、`getUseHyperCycle` 等。

#### `PathNode`（路径树节点）
发布订阅流路径树中的节点，可引用父节点，持有设备或交换机、子节点列表，以及（若为交换机）指向每个子节点的流片段。

- 关键方法：`addChild(Object node)`、`getParent / setParent`、`getNode`、`getChildren`、`addFlowFragment / getFlowFragments`。

#### `PathTree`（路径树）
用于描述发布订阅流的路径，本质是一棵 `PathNode` 树。

- 关键方法：`addRoot(Object node)`、`changeRoot(PathNode)`、`searchLeaves(PathNode)`、`getLeaves()`、`searchNode(String name, PathNode)`、`getRoot / setRoot`。

### 6.3 网络层（`network` 包）

#### `Network`（网络拓扑，实现 `Serializable`）
聚合设备、交换机、流，交给调度生成器遍历并建立调度规则。

- 属性：`devices`、`switches`、`flows`、`timeToTravel`、`jitterUpperBoundRange`；静态常量 `PACKETUPPERBOUNDRANGE = 5`（每条流默认调度 5 个包）、`CYCLEUPPERBOUNDRANGE = 25`。
- 关键方法：
  - `secureHC(Solver, Context)`：核心整体约束——逐流施加「延迟 ≤ 硬约束」「抖动 ≤ 上界」等约束；单播比较末跳调度时间与首跳出发时间，发布订阅对每个叶子及其父节点施加最大延迟/抖动约束。
  - `loadNetwork(Context, Solver)`：反序列化后重建 Z3 对象。
  - `preventCollisionOnFirstHop / assertRulesForCollisionPrevention`：防止同一源设备的多条流在首跳冲突。
  - `assertFirstSendingTimeOfFlows(Solver, Context)`：为所有流施加首发送时间约束。
  - `getFragmentsOfFirstHop`：收集首跳片段。
  - getter/setter 与 `addFlow / addSwitch / addDevice / getSwitch(name) / getDevice(name)`。

### 6.4 调度生成层（`schedule_generator` 包）

#### `ScheduleGenerator`（调度生成器）
基于给定 `Network` 生成调度，创建日志文件并把时序属性回填到周期与流中。

- 属性（开关，通过命令行/方法控制）：`exportModel`、`generateXMLFiles`、`generateSimulationFiles`、`serializeNetwork`、`loadNetwork`、`enableConsoleOutput`、`enableLoggerFile`、`generateJSONOutput`。
- 关键方法：
  - `generateSchedule(Network net)`：核心方法。创建 Z3 上下文 → 用策略 `qfufbv_ackr` 建求解器 → 配置网络（或加载网络）→ `solver.check()` → 若 `SATISFIABLE` 则 `getModel()` 取值 → `Printer.generateLog` 写 `log.txt` → 按开关导出模型 / 生成 NetConf XML / 序列化网络 / 生成仿真文件 / 生成 JSON 输出。
  - `generateSchedule(String topologyFilePath)`：从输入文件路径解析网络后调用上述方法（命令行入口使用）。
  - `configureNetwork(Network, Context, Solver)`：流的转换与周期登记、流的 `toZ3`、交换机的 `toZ3`、首跳防冲突、首发送时间约束、设抖动上界、调用 `secureHC`。
  - `createContext / closeContext`：Z3 上下文创建/关闭（启用模型生成）。
  - `serializeNetwork / deserializeNetwork / loadInstanceCounters`：网络序列化/反序列化及实例计数器恢复。
  - `generateSimulationFiles(Network)`：创建 `nestSched/` 目录并调用 `NestSchedXMLGen / INIGen / NEDGen` 生成仿真文件。
  - `setParameters(String[] args)`：解析命令行开关（`-exportModel`、`-generateXMLFiles`、`-generateSimulationFiles`、`-serializeNetwork`、`-loadNetwork`、`-enableConsoleOutput`、`-enableLoggerFile`、`-disableJSONOutput`）。

#### `ScheduleType`（枚举）
调度类型：`MICROCYCLES`（微周期）、`HYPERCYCLES`（超周期）、`DEFAULT`（默认走微周期）。

#### `SlotArrangementMode`（枚举）
时隙排列模式：`MAXCAPACITY`（各优先级满容量）、`EQUALDISTRIBUTION`（均分）、`AGRESSIVEDESCENT`（逐级减半）。

### 6.5 接口管理层（`interface_manager` 包）

#### `GenericParser`（接口）
定义解析器契约：`parseInput()`、`parseInputContent(String)`、`setPrinter(Printer)`。

#### `JSONParser`（实现 `GenericParser`）
解析 JSON 输入构建网络拓扑，并把输出写为 JSON。

- 关键方法：
  - `parseInput / parseInputContent`：把 JSON 内容转为 `Network`（依次解析交换机、设备、端口、流）。
  - `getListOfSwitches / getListOfDevices / setPortsOfSwitch / getListOfFlows`：内部解析各要素。
  - `getArrayFromElement`：从 JSON 对象取数组元素（容错处理）。
  - `convertSpeedUnits / convertSizeUnits / convertTimeUnits`：单位换算（如 `1.5 Mb`、`1.5 ms`、`1 Gbit/sec`）。
  - `extractSwitchInfoList / extractFlowInfoList / recursiveHopInfoGathering`：抽取调度结果用于 JSON 输出。
  - `generateOutput(Network)`：生成 JSON 输出文件。

#### `XMLParser`（实现 `GenericParser`）
解析 XML 输入。其实现借助 `org.json.XML.toJSONObject` 将 XML 转为 JSON，再复用 `JSONParser` 解析（`parseInputContent`）。

#### `ParserManager`（解析器调度）
按内容首个非空白字符判断输入类型并分派解析器：`<` → `XMLParser`；`{`/`[` → `JSONParser`。

- 关键方法：`getFirstNonWhitespace`、`getParser(String)`、`parseFromFile()`、`parseFromContent(String)`、`parseOutput(Network)`（走 JSON 输出）。

#### `Printer`（日志/输出）
负责把求解结果写入日志与终端。

- 关键方法：`stringToDouble`、`writePathTree`、`generateLog(String, Network, Context, Model)`、`printDataOnTree`、`exportModel(Solver)`、`printOnConsole(Network)`、`printIfLoggingIsEnabled`、`printInLineIfLoggingIsEnabled`、`logIfLoggingIsEnabled`、`logInLineIfLoggingIsEnabled`。

#### `SizeUnits` / `TimeUnits`（枚举）
可识别的数据量单位（BIT/BYTE/KBIT/MBIT/GBIT/KBYTE/MBYTE/GBYTE…）与时间单位（US/MS/S…），用于输入的统一解析。

### 6.6 NetConf 导出（`sched2netconf` 包）

#### `XMLExporter`
将求解得到的调度导出为 NetConf 门控列表（GCL）XML。

- 关键方法：
  - `XMLExporter(Network net)`：构造即导出。
  - `createGCL(int id, long timePeriod, int gateState, boolean isGuardBand)`：生成门控列表条目。
  - `setupXMLNodes / createTagWithValue / writOptions / writeDataToXML / prettyPrint`：构建并写出 XML。

#### `Triple`
工具类，存储 `(queueID, slotStart, slotDuration)` 三元组，用于门控列表。实现 `Comparable`（按 `slotStart` 排序，`equals`/`hashCode` 亦以 `slotStart` 为准）。

### 6.7 仿真文件生成（`nest_sched` 包）

将 `Network` 对象中的调度值转译为 NeSTiNg（OMNeT++ + INET）仿真模型文件。

| 类 | 职责 | 输出文件 |
| --- | --- | --- |
| `NestSchedXMLGen` | 生成过滤数据库（路由）、门控调度、流量生成器等 XML | `Routing.xml`、`PortScheduling.xml`、各 `dev*.xml`、`emptyFlow.xml` |
| `NestSchedNEDGen` | 生成网络描述文件与设备文件 | `NestSched.ned`、`NestSchedDev.ned` |
| `NestSchedINIGen` | 生成仿真初始化文件（含 MAC 地址、流量参数） | `NestSched.ini` |
| `NestSchedAux` | 辅助工具（处理设备/端口等辅助逻辑） | — |

### 6.8 入口层

#### `Main`（`com.tsnsched.core.Main`）
程序入口：

- 无参数：运行内置示例 `SmallScenario.runTestCase()`。
- 有参数：`gen.setParameters(args)` 解析开关后，以 `args[0]` 作为输入文件调用 `generateSchedule(inputFile)`。

---

## 7. 核心调度流程

`ScheduleGenerator.generateSchedule(Network net)` 的完整执行序列：

1. **创建上下文**：`createContext()` 生成启用模型生成的 Z3 `Context`。
2. **创建求解器**：使用策略 `qfufbv_ackr` 构造 `Solver`。
3. **配置网络**（`configureNetwork`）：
   - 对每条流：设置 `Printer` → `modifyIfUsingCustomVal` → `convertUnicastFlow`（统一为树结构）→ `setUpPeriods`。
   - 对每台交换机：`setUpCycleSize`。
   - 流 `toZ3`、交换机 `toZ3`（施加周期上下界、周期起始非负、周期起始统一为 0 等约束）。
   - `preventCollisionOnFirstHop`（首跳防冲突）、`assertFirstSendingTimeOfFlows`。
   - 设抖动上界为 25，调用 `secureHC`（逐流施加延迟/抖动硬约束）。
4. **求解**：`solver.check()`。
5. **取值与输出**（若 `SATISFIABLE`）：
   - `solver.getModel()` → `model.evaluate(switch1CycDuration, ...)`。
   - `Printer.generateLog("log.txt", net, ctx, model)` 写日志。
   - `Printer.printOnConsole(net)` 打印终端。
   - 按开关：`exportModel` → 导出模型；`generateXMLFiles` → `new XMLExporter(net)`；`generateSimulationFiles` → 生成 NeSTiNg 文件；`generateJSONOutput` → `parserManager.parseOutput(net)`。
6. **清理**：`closeContext(ctx)`。
7. 打印各阶段耗时与总执行时间。

---

## 8. 输入与输出格式

### 8.1 输入

TSNsched 支持三种输入方式：

1. **JSON 文件**（推荐）：描述交换机、设备、端口、流，支持带单位字符串（经 `convertSizeUnits`/`convertTimeUnits`/`convertSpeedUnits` 换算）。
2. **XML 文件**：由 `XMLParser` 先将 XML 转为 JSON 再解析。
3. **Java 代码**：直接以 Java API 构建 `Network`（含 `runTestCase()` 方法，供 `GenerateScheduleJavaInput` 反射调用 `UseCase.runTestCase()`）。

示例（JSON 输入见 `Script/input.json` 与 `src/com/tsnsched/generated_scenarios/input.json`）；Java 输入见 `Script/example.java`。

### 8.2 输出

| 输出 | 内容 | 说明 |
| --- | --- | --- |
| `log.txt` | 求解日志 | 交换机/端口/流片段信息、优先级、时隙起止、包的到/发/调度时间 |
| `output.json` | 结构化调度结果 | 由 `JSONParser.generateOutput` 生成，供外部消费 |
| NetConf XML | 门控列表（GCL） | 由 `XMLExporter` 生成，默认输出到 `XMLExporterFiles/` |
| `network.ser` | 序列化网络 | 可反序列化后继续使用（`-serializeNetwork`/`-loadNetwork`） |
| `nestSched/*` | 仿真文件 | `.ned`、`.ini`、`.xml`，供 NeSTiNg/OMNeT++/INET 仿真 |

命令行脚本 `generateSchedule.sh` 会把结果整理为：`output/<name>.out`（Z3 模型与用户输出）、`output/<name>.log`（日志）、`output/output.json`。

---

## 9. 项目运行方式

### 9.1 环境要求

- Java 1.8.0_181（JDK 8）
- Z3 4.8.0.0
- GNU bash 4.4.19+
- （可选）Eclipse IDE 4.8.0、（可选）NeSTiNg + OMNeT++ 5.5.1 + INET 4.1.2（仿真）

### 9.2 一键安装依赖

```bash
sudo ./install-dependencies.sh   # 克隆并构建 Z3（--java），安装 openjdk-8，并运行示例
```

### 9.3 命令行运行

前提：已安装依赖。进入 `Script/` 目录：

```bash
cd Script/
./generateSchedule.sh example.java     # Java 拓扑用例
# 或
./generateSchedule.sh input.json       # JSON 拓扑用例
```

`generateSchedule.sh` 的处理逻辑：

- 若参数以 `.java` 结尾：复制为 `UseCase.java`，把 `package schedule_generator;` 替换为 `import schedule_generator.*;`，把 `GeneratedCode` 替换为 `UseCase`；编译 `GenerateScheduleJavaInput.java` 后运行。
- 否则：编译并运行 `GenerateScheduleJSONInput.java`，把参数作为 JSON 文件路径传入。
- 输出整理到 `output/`（`.out`、`.log`、`output.json`）。

### 9.4 作为库使用（Java API）

将 `TSNsched.jar` 与 `com.microsoft.z3.jar` 加入 classpath 后：

```java
import schedule_generator.*;

Device devA = new Device(1000, 0, 1000, 1625);           // 周期、首发送时间、硬约束、包大小
TSNSwitch sw = new TSNSwitch("sw", 100, 1, 125, 1, 400, 3000);
Cycle cycle = new Cycle(50);
sw.createPort(devA, cycle);

Flow flow = new Flow(Flow.PUBLISH_SUBSCRIBE);
flow.setStartDevice(devA);
flow.addToPath(devA, sw);

Network net = new Network(25);    // 抖动上界
net.addDevice(devA);
net.addSwitch(sw);
net.addFlow(flow);

ScheduleGenerator scheduleGenerator = new ScheduleGenerator();
scheduleGenerator.generateSchedule(net);

// 读取结果
flow.getAverageLatency();
cycle.getCycleDuration();
```

### 9.5 运行内置示例（IDE / 直接运行）

直接运行 `com.tsnsched.core.Main`（无参数）会执行 `SmallScenario`；或运行 `Script/GenerateScheduleJSONInput` / `GenerateScheduleJavaInput`。命令行参数开关示例：

```bash
java -classpath ".:libs/*" com.tsnsched.core.Main input.json -enableLoggerFile -generateSimulationFiles
```

常用开关：`-enableConsoleOutput`、`-enableLoggerFile`、`-generateXMLFiles`、`-generateSimulationFiles`、`-serializeNetwork`、`-loadNetwork`、`-exportModel`、`-disableJSONOutput`。

### 9.6 生成自定义拓扑

使用 `ScenarioGenerator` 按需生成 Java 拓扑文件：

```bash
cd ScenarioGenerator/
javac *.java
java ScenarioGenerator
# 生成 GeneratedCode.java（含拓扑描述）
```

### 9.7 仿真验证（NeSTiNg）

1. 用 `-generateSimulationFiles` 开关生成 `nestSched/` 目录文件。
2. 按需修改 INET 的 `INTERFRAME_GAP_BITS`（96→0）、NeSTiNg 的 `standardTrafficClassMapping` 与 `VlanEtherTrafGenSched`（详见 `README.md`）。
3. 将 `nestSched/` 复制到 NeSTiNg `simulations/examples` 目录，在 OMNeT++ 中运行仿真。

---

## 附：关键约束小结

| 约束类别 | 实现位置（类.方法） |
| --- | --- |
| 周期时长上下界 | `TSNSwitch.toZ3` |
| 周期起始非负/统一为 0 | `TSNSwitch.toZ3` |
| 最大周期起始 ≤ 首个包到达 | `TSNSwitch.toZ3` |
| 时隙绑定/未用槽置零 | `Port.bindTimeSlots` / `zeroOutNonUsedSlots` |
| 包到/发/调度时间关系 | `Port.setupDevPacketTimes` / `Flow.nodeToZ3` |
| 相邻片段链接 | `Flow.bindAllFragments` |
| 首发送时间约束 | `Flow.assertFirstSendingTime` |
| 首跳防冲突 | `Network.preventCollisionOnFirstHop` |
| 延迟硬约束 | `Network.secureHC` |
| 抖动上界 | `Network.secureHC` |