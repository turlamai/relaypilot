# RelayPilot DESIGN.md — 设计契约（pre-UI brief · 单一真源）

RelayPilot 当前是架构实验（CLI + 回环引擎纵切），**尚无任何产品界面表面**。本文件是
pre-UI brief：在首个原生宿主（ROADMAP M2）开工前，先把品牌基调、HIG 原则与信息架构
边界钉下来，是对 AGENTS.md「设计流程（原型先行）」中「尚未建立时随首个 UI 切片建立」
条款的主动履行。完整契约（组件词汇 + 4–6 屏原型）随首个 UI 切片在同一切片内建立。

## Brief（2026-11-11）

- **目标**：让 M2 桌面宿主开工时零猜测——品牌色板、HIG 承诺、信息架构边界先于代码钉定；
  保证「canonical profile → DecisionTrace → engine artifact」这条可解释性主角在未来的
  界面上站出来，而不是做成又一个「Xray GUI」。
- **产品定位边界**：本地优先的网络工具箱与架构实验。无 VPN/节点/流量服务，无预售，
  无商业激活（PRICING `2026-10-v2`：实验冻结、暂不销售）；所有界面概念永远不暗示
  已运营的服务或网络。
- **本契约的 Exit 条件**：首个原生宿主切片内完成 ① 本 tokens 与原生平台实现核对固化
  ② 补齐组件词汇 ③ 4–6 屏 HTML 原型按 HIG 基准评审通过 ④ 本文件升级为完整契约。
  在此之前本文件不阻塞任何 CLI/引擎切片。
- **不在范围**：商业/收费/授权 UI、订阅与账户体系、任何「节点市场/流量套餐」类概念、
  CLI/golden 契约与 schema 变更、跨平台 UI DSL（Rivet 边界：各宿主第一方原生 UI）。

## 设计原则（UI 启动时必须遵守的 HIG 内核）

- **清晰优先，内容至上**：chrome 退后；Profile、规则与 DecisionTrace 是每屏主角，
  装饰不与内容争注意力。
- **可解释性一等公民**（产品特有）：「为什么走了这条路」必须比「连上了没有」更可追溯；
  每个连接决策都能回溯到规则来源、策略解析与 trace ID。
- **直接操纵**：Profile 与规则就地编辑所见即所得；导入即预览 diff 与不支持字段报告，
  不做黑盒转换。
- **反馈及时**：引擎会话生命周期（validate / start / stop / 事件）永远有进行态与完成态，
  永不静默；后台任务可感知。
- **防错一致**：影响网络路径的操作需显式确认与可回滚路径；跨平台快捷键语义一致；
  AI 永远停在预览，apply 是用户的显式动作。
- **键盘可达，层级克制**：核心操作全部键盘可达并有可见入口；bg/surface/raised 三层足够，
  accent 只给交互与状态。

## 交互参照（Surge · interaction reference，非像素模板）

Surge（macOS/iOS 网络调试工具）的目标用户与 RelayPilot 高度重叠（Surge 子集导入
是 M2 一等能力），其交互范式作为**参照**以降低迁移成本。内部契约声明参照对象
（同 taskly 契约点名 Things/Reminders 的做法）；对外文案与产品叙事**不提对标物**。

**参照 Surge 的范式**：Profile 列表 + 选中即用的顶层组织；事件/日志流按时间倒序；
配置导入即校验并报告问题行；规则集只读查看优先于表单编辑；设置分节样式。
参照对象以 **Surge for macOS** 为主（同为桌面），iOS 手势范式不直接映射。

**有意偏离（品类差异化，不照抄）**：
- **DecisionTrace 优先于流量仪表**——主屏第一主角是「为什么走了这条路」的
  可解释链，不是实时速率图/请求流；这是与 Surge 的品类区分点，也是不变式 2 的落点。
- **无流量统计实时图**——M2 无流量采集；能力落地前任何速率/流量可视化都不出现
  （不变式 3：不暗示已运营网络）。
- **规则编辑 = 文本 + 校验 + AI patch 预览**，非 GUI 策略组表单编辑器（M2 边界）。
- **三平台原生机制**——修饰键/菜单/对话框按平台映射与差异声明节落地。

## Tokens（预钉语义 · 自 site-kit 家族套件推导）

**来源注明**：值真源 = `site/family.css`（家族 site-kit 套件，官网 `relaypilot.jrtx.site`
与家族站点同源的品牌色板）与原型 `design/prototype/shared.css`（预钉值的可执行载体）；
`--ok` / `--warn` / `--danger` 暗态取官网既有状态色原值，亮态按对比度加深推导，
`--danger` 暗态与官网窗口红点同源。本表只记语义与推导依据。
**首个 UI 切片时与原生实现核对后固化**；在此之前变更 tokens 先改原型再改本表语义。

| Token | 语义 |
|---|---|
| `--bg --surface --raised --line` | 画布 / 卡片浮层 / 悬浮选中底 / 分隔 |
| `--ink --mute --faint` | 主/次级/辅助文字三档（faint = site-kit text-3） |
| `--accent --accent-soft` | 选中/链接/主操作/进行态 + 弱底徽标 |
| `--ok` | 校验通过/会话正常 |
| `--warn` | 待验证/警告（架构 alpha 状态色） |
| `--danger` | 错误/破坏性操作 |

- **字体**：原生 UI 一律平台系统字体栈（SwiftUI / WinUI 3 / GTK4 各自系统字体 +
  PingFang SC / 微软雅黑 / Noto Sans CJK），不引入 Web 字体；DecisionTrace、CLI 输出与
  artifact 摘要用等宽栈 `ui-monospace, "SF Mono", "Cascadia Code", "JetBrains Mono", monospace`。
  官网的 Newsreader/Inter 属网站门面，不进产品 UI。
- **圆角**：沿用 site-kit 三档——控件 8 · 卡片 12 · 浮层 16（窗口圆角交给平台窗口管理）。
  **间距节奏**：4/8/12/16/24。**动效**：120–200ms ease，不过度。
- **语言**：界面文案跟随产品文档政策（AGENTS.md Documentation languages）：英文默认 +
  完整 zh-CN 双源，API/协议标识符与命令保持原文。

## 计划的信息架构边界（M2 桌面首屏候选 · 非已承诺交付）

基于 ROADMAP M2「First usable desktop path」与 ARCHITECTURE 控制面分层圈定；首个原型
评审时以此为起点，不虚构任何功能：

- **连接主视图**：引擎会话状态（未运行/校验中/运行中/已停止）、连接/断开、当前选中出口、
  会话事件摘要（M2：connect/disconnect/status）。
- **DecisionTrace 检查器**：规则命中链 → 策略组解析 → 选中出口 → 步骤/警告 → trace ID
  （M2：minimal connection/DecisionTrace inspector）。
- **Profile 库**：canonical Relay Profile 列表与校验状态；Surge 子集导入即预览并报告
  不支持字段（M2）。
- **诊断**：DiagnosticBundle 查看与脱敏导出。
- **同步**：本地文件夹边界（provider 中立，用户自有目录）。
- **AI patch**：redact → typed patch → 模拟 → 预览 → 用户 apply 的全链路呈现。
- **设置**。

信息架构外**禁止出现**的概念：节点/订阅/流量售卖、账户与授权墙、任何已运营服务叙事。

## 不变式

1. **契约先行**：任何 UI 代码进仓库前，`design/` 必须已有对应契约与原型版本；
   改界面先改原型再改代码。
2. **可解释性不被 UI 修改**：DecisionTrace、trace ID、adapter 版本、digest、source map
   在任何界面中可见、可回溯，UI 不得改写、隐藏或「美化」这些事实字段。
3. **诚实状态**：界面只陈述已验证事实（已验证/待验证/不可用），架构能力不得表述为产品
   能力；永远不出现 VPN 服务、节点资源、流量套餐或已运营网络的暗示。
4. **亮暗成对**：任何界面状态亮暗双态同钟设计，不存在只有暗态的界面。
5. **accent 克制，状态色独立**：accent 只给连接主操作、选中、进行态与链接；
   ok/warn/danger 是独立的语义色，不与 accent 混用挪用。
6. **破坏性防错**：连接/断开/应用 patch/删除 Profile 需显式确认与可回滚路径；
   AI 永远停在预览，apply 是用户的显式动作。

## 组件词汇（预钉 · M2 宿主开工时与原生实现核对固化）

| 组件 | 规范 |
|---|---|
| 会话状态徽标 | 胶囊形：`未运行`(muted) / `校验中…`(warn, 转圈) / `运行中`(ok) / `已停止`(muted)——文字必须与徽标色一致语义 |
| 连接主按钮 | 36px 高、radius 8、accent 底白字（停止时变为 danger 描边「断开」）；状态未就绪时禁用 |
| Trace 行 | 等宽栈单行：步骤序号 + 动作 + 对象；命中/跳过以 ok/mute 左侧竖线区分；点击展开规则原文引用 |
| Trace ID 条 | 等宽、可复制；trace ID + adapter 版本 + digest 三事实常驻（不变式 2） |
| Profile 卡 | 卡片 12px 圆角：名称 + 校验徽标（已验证 ok / 待验证 warn / 不可用 danger）+ 引擎目标 + 入口数；点击进详情 |
| 导入预览表 | 双栏 diff：支持字段 vs 不支持字段（warn 徽标逐条列出）；导入按钮在确认前禁用 |
| 警告条 | surface 底 + warn 左边线；文案含可执行下一步 |
| 事件摘要列表 | 会话事件倒序，时间戳等宽；每行可展开到 DecisionTrace |
| 设置行 | 与 taskly 同款：细线分隔行 + 控件右置 |

## 平台映射与差异声明（预钉 · 宿主选定后升级为落点表）

M2 首个宿主未定（macOS / Windows 优先，ROADMAP「preferably macOS or Windows」）。
**统一层**（三平台必须一致，原型已锁定）：信息架构（7 屏边界）、连接/断开与校验流程、
DecisionTrace 的步骤-策略-出口叙述顺序、trace ID/adapter/digest 事实字段、快捷键语义、
语义色与层级词汇。**因地制宜层**（选定宿主后按平台惯例落地，不预画像素）：

| 维度 | macOS | Windows | Linux |
|---|---|---|---|
| 修饰键 | ⌘ | Ctrl | Ctrl |
| 命令入口 | 原生菜单栏 | 菜单栏/命令行内 | 菜单栏 |
| 字体 | 系统栈 + PingFang SC | 系统栈 + Microsoft YaHei | 系统栈 + Noto Sans CJK |
| 原生控件 | SwiftUI 控件 | WinUI 3 控件 | GTK4 控件 |

**差异声明纪律**（taskly 漂移台账 D8 的教训）：任何宿主特例必须先写进本节
（或未来宿主切片的 PRODUCT-SPEC）才能实现；未声明的宿主差异按违约处理。
跨设备用户提示（可选）：连接状态摘要进入系统托盘/菜单栏由宿主惯例决定，语义保持
「连接主视图是唯一真相源」。

## 原型（design/prototype/，2026-11-11 认领切片）

四屏 × 亮暗，严格用上述 tokens 与组件词汇渲染，仅呈现已验证的后端能力：
① `connect.html` 连接主视图（会话生命周期 + 事件摘要）② `trace.html` DecisionTrace
检查器（规则链 → 策略 → 出口 → trace ID）③ `profiles.html` Profile 库 + Surge 导入
不支持字段报告 ④ `settings.html` 设置。HIG 自检通过后本契约升级为完整契约。
