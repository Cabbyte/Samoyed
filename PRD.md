# Samoyed 产品合同

- 版本：2.2 private beta
- 更新：2026-10-05
- 状态：当前实现与后续变更的产品边界

## 1. 产品目标

Samoyed 帮助一个人可靠地运行可复用的日常 Routine。用户通过起步模板、配置导入或授权的外部工具准备少数几种 Routine；weekday default 自动运行今天，只在例外日选择其他已有 Routine 或 No Routine。

iPhone 负责 Now、只读 Today、checklist 执行、Timeline Notes 和显式审批。Nest 提供同一用户的 Routine 编排与同步，离线时手机继续使用本地数据。

主要用户需要稳定的工作日、休息日、恢复日等生活结构、重复步骤和固定提示语。产品不扩展为团队协作、通用待办收集箱、项目管理、外部日历调度或手机端可视化 Routine 编辑器。

## 2. 文档职责

- 本文定义产品目标、范围、用户行为与验收标准。
- [README.md](README.md) 定义领域模型、结构约束、时间解析和同步边界。
- [Design.md](Design.md) 定义界面如何消费这些语义。
- [SystemSurfaces.md](SystemSurfaces.md) 定义 Widget、Live Activity 与 App Shortcuts。
- [Nest 状态](docs/samoyed-nest-status.md) 记录带日期的部署和验收证据；[运维手册](docs/samoyed-nest-operations.md) 定义发布与恢复操作。

历史截图、旧探索文档和未注册的功能不扩大当前范围。Figma `KMmryraXYpe4O2BTgadVjJ` 是视觉参考；数据正确性仍由领域规则保证。

## 3. 结构、执行与数据归属

### 3.1 Routine Definition

Routine Definition 定义 base/overlay blocks、时间关系、固定提示语、checklist 内容和 reminder 意图。Routine Config File 是它的一种传输形式；当前导入导出支持 YAML，不承诺其他格式。

结构与执行状态分离：完成 checklist 只改变具体日期的任务实例，明天再次运行时重新开始；完成状态不导出为 Routine 结构。`TemplateEngine`、`SavedDayTemplate` 等内部名称及已持久化字段为兼容保留，用户术语使用 Routine。

### 3.2 本地模式与 Nest 模式

| 模式 | 持久化和写入边界 |
| --- | --- |
| 本地模式 | App Group SQLite 保存本地文档，启动与执行不要求账号或网络。 |
| Nest 模式 | `https://samoyed.protium.top` 是账号数据的唯一可写服务；iPhone 保存分账号的本地副本、离线 outbox、同步游标和冲突档案。 |
| 旧 Sites | 只读历史入口，不恢复业务写入，不自动合并账号身份。 |

用户授权的 MCP/外部工具可以在 Nest 编排 Routine、星期规则、日期例外和当日修正，并记录执行事件或 Notes。每次修改必须遵守校验、预期 revision 和幂等 operation ID。连接 Nest 不改变单人产品定位，也不要求本地执行始终在线。

离线编辑不能被较新的同步快照静默丢弃。冲突必须保留本地和远端内容并提供明确处理入口。超时重试复用完全相同的 operation ID、payload 和 expected revision；更改内容必须使用新 operation ID。

## 4. 每天如何运行

1. 首次打开可安装 Starter Routine、导入配置、连接 Nest，或明确继续使用 No Routine。
2. 已设置 weekday default 时自动生成今天，不要求每天重复确认。
3. 日期选择或日期例外优先于星期默认；选择 No Routine 是合法状态，不代表加载失败。
4. Nest 的 Routine 和星期规则修改默认从账号时区的明天生效；日期例外明确指向某一天。
5. 时间轴展示实际保存的 DayPlan 快照及其来源，不用最新规则的标题冒充历史来源。
6. 已开始、已执行或已修正的块按完整子树保护。新 Routine 与这些子树冲突时保留此前有效快照和来源，不能直接拼接出非法层级或缩短历史范围。
7. 无执行的未来计划仍可按有效规则重新物化。受保护的历史快照、任务实例和 Notes 关联不得因此丢失。

“选择了哪个规则”和“当前展示哪个有效快照”可能暂时不同；界面必须表达真实来源。修复损坏的快照通过显式、版本检查和可审计的恢复完成，不清空数据库或伪造起步数据。

## 5. iPhone 信息架构

| 页面 | 核心职责 | 允许的操作 |
| --- | --- | --- |
| Now | 当前状态、固定提示语、当前任务来源与下一状态 | 完成/撤销 checklist、记录 Feedback、打开 Today、显式开始/结束 Live Activity。 |
| Today | 按日期查看只读层级时间轴，穿插 Timeline Notes | 查看 block、完成/撤销 checklist、选择已有 Routine/No Routine、增改删 Notes、回到今天当前时间。 |
| Library | Routine 资产、Nest 与设置入口 | 只读预览、导入导出、Usual Week、Suggestions、Planner 状态、Appearance、同步和冲突处理。 |

Today 不提供 block 创建、删除、拖拽 resize、reparent、cancel 或 checklist/reminder 内容编辑，也不把当天计划保存回 Routine。打开 block 详情不应改变日期；Today 按钮回到当前日期和时刻，不自动打开 inspector。

Now 的任务面板来自当前 active chain；上层任务全部完成后可回退到父层。空闲、No Routine、任务全部完成和数据读取失败必须有不同表现。

## 6. 提示语、Notes、Feedback 与 Suggestions

- **固定提示语（guidance）**属于 Routine/Block 结构；为配置兼容，wire 字段仍可叫 `note`，在 Today 中只读。
- **Timeline Note** 是独立、可编辑和可删除的记录。以 `occurredAt` 定位时间轴，保留 IANA 时区，可关联具体 block instance，也可独立存在；不占用日程时长，不改变 checklist。
- **Feedback** 是当前保留的 append-only 本地反馈事件。它不直接修改 Routine、DayPlan 或 checklist；不把 Feedback 的本地存储误称为已完成远端同步。
- **Suggestion** 先进入 Inbox，经用户审批后应用。Daily-plan Suggestion 只影响目标日期；Routine-improvement 创建可追溯新版本，保留已经物化的 Today。涉及执行状态替换时必须明确确认。
- **Planner** 是可选接口，没有真实配置时显示 disconnected；它不能静默修改正在运行的计划。Nest 账号同步与 Planner 连接是不同能力。

Notes/执行状态通过 Nest 同步，不等于所有本地 Feedback、Planner provenance 或 UI 状态都已实现同步。

## 7. 导入、系统入口和兼容

配置导入必须先校验和预览，再由用户确认 Import、Replace 或 Keep Both。导入属于 Routine Library，不直接替换今天的执行快照。在 Nest 账号分区中的写入通过正常同步流程发送；配置 URL 本身不建立轮询或持续订阅。

支持的 deep link：

- `samoyed://import-routine?v=1&payload=<base64url-yaml>`，解码后最多 32 KiB。
- `samoyed://import-routine?url=<https-url>`，最多 512 KiB；Debug 额外支持 localhost HTTP。
- `samoyed://import-suggestion?v=1&payload=<base64url-json>`，导入后等待审批，不自动应用。

Home/Accessory Widgets、Live Activity、Dynamic Island 和六个 App Shortcuts 共享领域规则与持久化。Widget/Live Activity 的完成动作幂等且仅完成明确目标；Live Activity 必须显式开始。

通知调度、Notification Actions、Home Screen Quick Actions 和 Control Widgets 不在当前生产范围。ReminderRule 继续作为配置数据保存。旧版本遗留的通知/快捷项清理及数据迁移保留；不因清理代码而更换 Bundle ID、App Group、URL scheme、SQLite 分区或历史字段。

## 8. 质量与验收

- 空数据首次激活有效，读取失败不回退成样例数据。
- 默认自动运行、日期例外、No Routine、跨午夜和版本生效日期可解释。
- 切换 Routine 后结构仍合法；已执行、已开始、已修正和 Note 关联记录得到保护。
- 完成/撤销、离线写入、丢失响应重试、重启和回网同步不丢失或重复事件。
- Now、Today、Routine 来源及系统表面的状态一致。
- 长标题、长 Notes、重叠起点、Dynamic Type 与 VoiceOver 有可用路径；控件使用稳定语义标识。
- 本地测试、CI、TestFlight 处理成功、用户初步验收和完整真机测试分别记录，不互相替代。

2026-10-05 用户确认已有版本初步验收无问题。此前人工飞行模式、两台实体设备并发等专项测试仍按实际证据记录，不能由这次初验推定全部通过。

## 9. 成功指标与新增需求

成功看默认 Routine 是否可靠自动运行、用户是否高频使用 Now、是否通过 Today 理解一天、是否能轻量完成 checklist，以及外部编排是否减少手机上的组织负担。

新增功能先说明用户问题、所在使用阶段、可观察结果和最小验证方式。优先解决日常执行和数据可靠性，再根据真实使用反馈扩展能力。
