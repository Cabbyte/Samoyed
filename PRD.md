# Samoyed PRD

- 版本：Frozen contract v1.0
- 日期：2026-08-14
- 状态：Implementation contract
- 文档目的：落实 Frozen Figma `KMmryraXYpe4O2BTgadVjJ`：iOS 是 local-first Routine 运行终端，负责展示、checklist、append-only Feedback 与 Suggestion 审批；本地文档是业务真相。

## 1. 一句话定义

Samoyed 不是待办清单，也不是日历，也不是手机上的日程编辑器。

Samoyed 是一个单人使用的日常生活辅助 App：用户运行少数几种已批准 Routine，weekday default 自动物化今天；需要例外时从已有 Routine 或 No Routine 中选择。App 在一天中持续、温和地展示当前状态、固定提示语和 checklist。

## 2. 产品本质

Samoyed 的本质不是“帮用户在手机上规划今天”，而是“把已经定义好的 routine 可靠地运行起来”。

它服务的不是：

- 零散、一次性的事务管理
- 项目管理
- 每天不断新增事项的 inbox 工作流
- 日历事件同步和调度
- 在 App 里拖拽、编辑、微调当天日程
- 手机端 routine 编排器或可视化流程编辑器

它服务的是：

- 用配置文件描述的、可复用的生活结构
- 稳定的工作日、休息日、恢复日、训练日等 routine
- 在特定状态下反复出现的 checklist
- 在特定状态下反复需要看见的 note
- 一天中不同状态之间的平滑切换
- 系统表面上的轻量陪伴与快速完成

用户每天不需要重新规划或确认。核心体验是默认 Routine 自动运行；只有今天确实不同，才通过 Today 的当前 Routine 入口选择其他已有 Routine 或 No Routine。Today 的结构始终只读。

## 3. 产品定位

### 3.1 产品类别

Samoyed 位于以下类别的交叉点：

- config-defined routine runner
- structured lifestyle app
- routine operating system
- day-structure viewer
- calm execution tool
- checklist-based daily companion

### 3.2 与常见产品的根本区别

大多数效率产品的底层逻辑是：

- 用户不断添加任务
- 系统帮助排序、归类、提醒
- 今天要做什么，取决于任务列表里新增了什么

Samoyed 的底层逻辑是：

- 用户或外部工具先用 Routine Definition 定义几种可运行的 routine
- weekday default 自动选择并运行 routine；用户只处理当天例外
- App 把这个 routine 物化为当天的运行视图
- 一天中的提醒、任务、备注都从 Routine Definition 结构中自然出现
- App 主要负责展示、提醒和 checklist 完成，不负责修改 routine 结构

换句话说：

- todo app 的核心是“收集事项”
- calendar app 的核心是“安排事件”
- visual planner 的核心是“在界面上编辑结构”
- Samoyed 的核心是“运行 Routine Definition 定义的结构”

## 4. 产品哲学

### 4.1 Routine Definition 是 routine 结构的唯一权威

Routine 的结构性内容只来自 `Routine Definition`。

`Routine Definition` 是格式无关的产品概念；它可以由 `Routine Config File` 承载。`Routine Config File` 的具体格式可以是 YAML、TOML、JSON，或未来支持的其他可校验配置格式。

Routine Definition 描述：

- routine 名称与说明
- base block
- overlay block
- 时间关系
- note
- checklist
- reminder rule

App 可以：

- 导入 Routine Config File
- 校验 Routine Definition
- 预览 Routine Definition
- 将 Routine Definition 加入本地 routine library
- 配置 weekday default，让稳定 Day Type 自动运行
- 物化当天运行结构
- 记录当天 checklist 完成状态

App 不可以：

- 在当天运行界面创建 block
- 在当天运行界面修改既有 block 的标题、时间、note、checklist 或 reminder
- 通过拖拽 resize block
- 通过取消 block 改变当天结构
- 从 Today 反向写回 Saved Day Type、Routine Definition 或 Routine Config File
- 成为 v1 的可视化 routine builder

### 4.2 结构状态与执行状态必须分离

Samoyed 必须清楚区分两类状态：

- 结构状态：由 Routine Definition 定义，描述一天应该如何运行。
- 执行状态：由 App 在某一天本地记录，描述 checklist 是否完成。

勾选 checklist 只改变当天的执行状态，不改变 Routine Definition。

这意味着：

- 同一个 Routine Definition 明天再次运行时，checklist 默认重新开始。
- 用户今天完成或未完成某项 checklist，不会改变 routine 本身。
- App 内部可以存储物化后的 day plan 或完成状态，但这些都不是 routine 结构的权威来源。

### 4.3 单人绝对成立

Samoyed 是绝对单人的产品。

这意味着：

- 不会有多人共享
- 不会有协作编辑
- 不会有团队视图
- 不会有评论、分配、同步给别人

即便未来支持导出或云端编排，那也只是为了更好地服务“同一个人”的 routine 生成与复盘，不改变单人本质。

### 4.4 本地优先，但允许外部编排

Samoyed 不做传统意义上的云同步。

正确的模型是：

- 外部工具或 AI 可以生成 Routine Definition 草案。
- 用户在本地预览、校验、确认并导入。
- 导入后的本地 Routine Definition 才能成为可运行结构。
- 云端不能直接成为产品真相。
- 云端不能无确认覆盖本地 routine library 或当天执行状态。

这使 Samoyed 可以天然与 AI 配合，但不会演变成一个依赖远程同步的 SaaS。

### 4.5 routine-first，而不是 task-first

Samoyed 优先描述的是 routine，不是一次性任务。

适合出现在 Routine Definition 中的是：

- 出门前带水杯
- 下班前收桌面
- 午饭后散步 10 分钟
- 睡前准备明天的衣服
- 健身前做热身

不适合出现在 Samoyed 中的是：

- 今天 3 点见客户
- 下周交报告
- 给某某发邮件
- 跟进某个项目

如果一次性事件真的会改变一天结构，它应当在 Routine Definition 之外被另行编排成新的 routine，或在未来由外部工具生成一个新的 Routine Definition 草案，而不是在 App 的当天界面中临时插入 todo。

### 4.6 手机端是运行终端，不是编排终端

Samoyed 的手机端重点不是创建或修改结构，而是运行结构。

端侧应该强调：

- 选择今天 routine
- 看现在
- 看今天整体结构
- 看 note
- 勾 checklist
- 接收温和提醒

端侧不应强调：

- 大量新建
- 复杂编排
- 高频录入
- 调整时间块
- 修改层级关系
- 把手机变成随时写入新任务的入口

### 4.7 提醒是配合，不是打断

Samoyed 的提醒不应像闹钟那样中断用户。

它更像一种配合式提示：

- 轻量出现
- 不抢夺焦点
- 不强制中断当前动作
- 在系统表面持续可见
- 帮用户回到当前 routine，而不是命令用户做事

## 5. 目标用户

### 5.1 核心用户

- 有稳定生活节律的人
- 希望把工作日过成“有结构的一天”的人
- 愿意用配置文件或外部工具定义 routine 的人
- 重视 routine 胜过追求任务清空的人
- 不希望每天在手机上反复输入新任务的人
- 需要柔和提醒与明确上下文的人

### 5.2 非目标用户

- 想把它当成通用 todo list 的用户
- 需要团队协作和任务流转的用户
- 主要管理项目型工作而非生活节律的用户
- 需要跨平台同步数据库的人
- 主要依赖外部日历来驱动一切的人
- 希望在手机上可视化搭建、拖拽、修改 routine 的用户
- 希望每天临时编辑详细日程的人

## 6. 典型使用场景

### 6.1 导入 Routine Config File

用户或 AI 工具准备一份承载 Routine Definition 的 Routine Config File，例如：

- 标准工作日
- 居家办公日
- 周五早下班
- 恢复日
- 健身强化日

用户在 App 中导入 Routine Config File，App 负责：

- 校验结构是否合法
- 展示可读预览
- 告知错误或缺失
- 将通过校验的 routine 加入本地 routine library

### 6.2 默认自动运行与当天例外

用户为一周配置稳定的 weekday default。每天开始时，App 自动选择并物化对应 routine，不要求重复确认。

自动选择后：

- 今天绑定到这一个 routine
- App 将 routine 物化为当天结构
- 当天的 block、note、checklist、reminder 都来自该 routine
- 用户不需要在手机上重复选择或规划日程细节

v1 中，每天只运行一个 Routine，不支持多个 Routine 组合运行。Today 的当前 Routine 入口允许显式改选当天 Routine 或选择 No Routine，且不修改 Usual Week。

### 6.3 日常执行

用户在一天中更多时候不是“规划”，而是：

- 看一眼当前 block
- 看当前 note
- 看当前应该做的 checklist
- 勾掉已经完成的固定步骤
- 接受轻量、非打断的提醒

### 6.4 今天与 routine 不完全匹配时

如果今天和默认 Routine 有差异，v1 提供两个窄入口：选择另一个已有 Routine，或选择 No Routine。

正确处理方式是：

- 必要时继续按当前 routine 展示与执行
- 通过 Today 的当前 Routine 入口选择另一个已有 Routine 或 No Routine
- Routine 本身需要改变时，导入新配置或审批一个经过本地校验的 Suggestion

App 不提供创建 block、拖拽 resize、reparent、取消并塌缩层级，以及标题、时间、note、checklist/reminder 的结构编辑能力。

### 6.5 外部智能编排

未来用户可在云端或 AI 工具中完成更复杂的 routine 编排，然后导入本地：

- AI 根据用户目标生成 Routine Definition 草案
- AI 输出新的 checklist 组合
- AI 输出新的 block/overlay 结构
- 用户在本地预览、校验、确认并导入

这是一种“外部生成 Routine Config File，本地确认运行”的结构，而不是云端同步或远程真相。

### 6.6 Feedback、Suggestions 与 Planner

- Feedback 是 append-only 本地事件；保存不得修改 Routine、DayPlan 结构或 checklist completion。
- Planner 只能生成 Suggestion，不能静默改变正在运行的计划。
- Daily-plan Suggestion 接受后只影响目标日期，不改变 Usual Week 或来源 Routine。
- Routine-improvement Suggestion 接受后创建可追溯的新 version，并保持已经物化的 Today 不变。
- Planner 是可选外部 seam。没有真实配置时 production 必须显示 disconnected；本地运行不依赖网络。
- 当前没有 production server、云同步、定时规划或 Feedback 远程同步。
- Suggestion 入口为 `samoyed://import-suggestion?v=1&payload=<base64url-json>`；内嵌最大 32 KiB，远程最大 512 KiB，HTTPS only，导入只进入 Inbox，不自动 apply。

## 7. 核心产品原则

- 配置权威：routine 结构只由 Routine Definition 定义。
- 单人优先：所有功能都围绕“一个人如何过好自己的一天”展开。
- routine 优先：固定模式比临时事务更重要。
- 默认自动：weekday default 每天自动运行，显式选择只用于当天例外。
- 展示优先：移动端首先负责展示与引导，而不是录入。
- checklist 优先于 todo：任务是动作清单，不是事项收集箱。
- 执行状态独立：完成状态属于某一天，不回写 Routine Definition。
- 温和提醒：提醒是配合式、伴随式，而不是侵入式。
- 本地为真：已确认导入的本地 Routine Definition 是可运行结构的来源。
- 外部辅助：AI 或云端可以生成 Routine Definition 建议，但不能直接替代本地确认。

## 8. 产品不是什么

Samoyed 不是：

- 待办应用
- GTD 工具
- 项目管理工具
- 外部日历外壳
- 习惯打卡产品
- 团队协作产品
- 多人共享家务板
- 手机端 routine 编辑器
- 可视化日程搭建工具
- 以快速创建任务为核心的手机工具
- 用拖拽、resize、reparent 来修正当天结构的 planner

## 9. 产品是什么

Samoyed 是：

- 一个 config-defined routine runner
- 一个让稳定 Day Type 自动运行、同时能处理当天例外的 routine runner
- 一个把 Routine Definition 物化为当天状态结构的系统
- 一个在正确时间显示正确 checklist 的陪伴工具
- 一个让重复生活模式可以被定义、复用、执行的系统
- 一个把“展示”和“现在该做什么”做到足够清晰的日常终端

## 10. 核心概念定义

### 10.1 Routine Definition

`Routine Definition` 是 Samoyed 中 routine 结构的唯一权威来源。

它是格式无关的结构定义，不等同于某一种文件格式。

它定义：

- routine 元信息
- block 层级
- 时间定义
- note
- checklist
- reminder rule

### 10.2 Routine Config File

`Routine Config File` 是承载 `Routine Definition` 的具体文件。

v1 可以优先支持一种格式，但产品概念不绑定格式。未来同一个 `Routine Definition` 可以由以下格式承载：

- YAML
- TOML
- JSON
- 其他可校验配置格式

### 10.3 Routine Library

`Routine Library` 是本地保存的、已导入并通过校验的 Routine Definition 集合。

它不是可视化编辑器。它负责：

- 展示已导入 routine
- 预览 routine 结构
- 管理配置文件导入/导出
- 支持每日 routine 选择

### 10.4 Daily Routine Selection

`Daily Routine Selection` 是某个本地自然日选择的唯一 routine。

v1 规则：

- 一个自然日最多运行一个 routine
- 不支持多个 routine 组合
- 不通过当天界面临时拼装 routine
- 优先由 weekday default 自动产生；显式选择只覆盖某个具体日期

### 10.5 Materialized Day

`Materialized Day` 是某个 Routine 在某个本地自然日上的运行快照。它通常由 Usual Week 自动生成，也可以由日期级 Routine 选择替换。

它包含：

- 从 Routine Definition 解析出的 block 结构
- 从 Routine Definition 解析出的 note
- 从 Routine Definition 解析出的 checklist
- 从 Routine Definition 解析出的 reminder
- 当天本地 checklist 完成状态

它不是 Saved Day Type 的结构权威；当天 checklist completion 只属于这个日期。

### 10.6 TimeBlock

一天中某一段状态。它不是日历事件，而是“我这段时间处于什么状态”。

### 10.7 BaseBlock

构成一天底层骨架的 block，例如起床、上午工作、午餐、晚间恢复。

### 10.8 OverlayBlock

叠加在更高层的状态，例如“深度工作”“周会”“健身”“出门准备”。

### 10.9 activeChain

某个时刻真正处于生效状态的一条父子链。

### 10.10 activeBlock

当前生效链条中最高层的那个 block。

### 10.11 taskSourceBlock

当前应该承接未完成 checklist 的 block。

用户当前所处状态，和当前任务应从哪一层出现，不一定是同一个概念。

### 10.12 Checklist Item

Samoyed 中的 checklist item 不是“今天有哪些事”，而是某个 routine 状态里的固定步骤。

正确示例：

- 出门前带门禁卡
- 午休前收电脑
- 训练后拉伸

错误示例：

- 今天完成投标方案
- 给客户打电话

### 10.13 Note

Samoyed 中的 note 更像“固定地对自己说的话”，是在某种状态下需要反复被看见的提示语。

例如：

- 午饭别吃太快
- 训练前先热身
- 晚上不要再开新工作

它不是临时记录，不是流水日志，不是会议纪要。

### 10.14 Execution State

`Execution State` 是某一天本地记录的执行状态。

v1 只需要支持：

- checklist item 是否完成
- 完成时间等轻量元数据

Execution State 不改变 Routine Definition。

## 11. 核心生活逻辑

Samoyed 的核心流程是：

### 11.1 先准备 routine

用户或外部工具用 Routine Definition 描述 routine。

App 只负责导入、校验、预览和保存本地副本。

### 11.2 默认运行今天

weekday default 自动决定今天运行哪一个 routine，例如：

- 标准工作日
- 居家办公日
- 加班日
- 休息日
- 健身强化日

### 11.3 然后运行一天

一旦选择 routine，用户不需要不断补充任务，也不需要调整时间块，而是沿着这一天的结构前进。

### 11.4 提示不是命令

当某个时间点到了，Samoyed 通过以下位置轻轻告诉用户：

- `Now`
- `Today`
- Widget
- Live Activity
- App Shortcut
- Shortcut
- 本地通知

信息包括：

- 现在到了哪个状态
- 该注意什么
- checklist 里还有什么

### 11.5 区分当天执行与结构改进

Today 只读展示既有 block；checklist completion 与 Feedback 不改变来源 Routine。如果用户发现 Routine 本身需要改变，结构改进必须成为可审批的 Suggestion 或新的导入文件：

- 用户在 App 外修改 Routine Config File
- 或让 AI/外部工具生成版本化 Suggestion
- 再导入 App 并由用户审批
- 之后用于未来日期

App 的当天运行界面不承担创建、删除、reparent、checklist/reminder 修改等复杂结构职责。

## 12. 主要产品目标

- 帮助用户用配置文件保存稳定 routine。
- 让 weekday default 自动运行，避免用户每天重复选择。
- 帮助用户在一天中始终知道自己处于哪种状态。
- 帮助用户在合适的时刻看到合适的 checklist。
- 让提醒尽量以温和方式出现，而不是成为中断源。
- 让手机端成为优秀的执行终端，而不是繁杂的录入或编辑终端。
- 为未来 AI 编排保留 Routine Config File 导入接口，但不放弃本地确认与本地运行。

## 13. 主要非目标

- 不做团队协作。
- 不做共享任务空间。
- 不做项目级事务管理。
- 不做通用待办收集箱。
- 不做外部日历集成。
- 不做传统云同步。
- 不做手机端可视化 routine builder。
- 不做任何当天结构编排或 block 属性编辑。
- 不做 block 创建、resize、reparent、cancel 工作流。
- 不做“手机上随时记一条任务”的主路径。
- 不做高侵入性的闹钟式提醒系统。

## 14. 信息架构

Samoyed 采用三个一级页面。

### 14.1 Now

定位：

- 今日运行终端
- 当前状态查看器
- checklist 执行面板

优先回答：

- 现在是什么状态？
- 我现在该注意什么？
- 我现在该做哪几个 checklist item？

允许：

- 查看当前 active chain
- 查看 note
- 勾选 checklist
- 跳转到 Today 查看整体结构

不允许：

- 创建 block
- 编辑 block
- 修改 checklist 内容
- 修改 note
- 修改 reminder
- 取消或替换当天 block

### 14.2 Today

定位：

- 今日结构查看器
- Routine Definition 的当天投影
- 只读时间轴

优先回答：

- 今天运行的是哪一个 routine？
- 今天整体结构是什么？
- 当前在哪个位置？
- 接下来会进入什么状态？

允许：

- 查看全天时间轴
- 查看 block 层级
- 查看 note、checklist 和 reminder
- 跳转到当前 block
- 从 Library 更换今天运行的 routine，前提是这是一次明确的日级选择
- 修正当天既有 block 的标题、开始/结束时间和 note；保存时必须明确说明 Saved Day Type 不变

不允许：

- 直接新增 base block 或 overlay block
- 拖拽调整时间
- resize block
- reparent block
- cancel block
- 修改当天 checklist 文本
- 修改 reminder 或层级
- 保存今天结构为新 routine

### 14.3 Library

定位：

- Routine Library
- Routine 导入、校验、预览和导出中心
- 今日 routine 选择入口

优先回答：

- 我有哪些可运行的 Routine Definition？
- 今天要运行哪一个？
- 某个 routine 的结构是否可读、合法、可运行？
- 如何导入外部编排结果？

允许：

- 导入 Routine Config File
- 校验 Routine Definition
- 预览 Routine Definition
- 导出 Routine Config File
- 从 library 中选择今天 routine
- 管理本地 routine 副本

不允许：

- 在 App 内可视化编辑 routine 结构
- 把当天执行状态写回 Routine Definition
- 把物化后的当天计划当成 routine 权威

## 15. 功能需求

### 15.1 Routine Library

功能定义：

- 用户可以导入 Routine Config File。
- App 对 Routine Config File 和 Routine Definition 做结构校验。
- App 展示 routine 预览，包括 block、overlay、note、checklist 和 reminder。
- App 将通过校验的 routine 加入本地 library。
- 用户可以导出已导入 routine 对应的 Routine Config File。

产品要求：

- Library 的重点是“可运行的 routine 资产”，不是设置页或编辑器。
- 预览必须让用户理解“这一天会怎么过”。
- 校验错误必须可理解，帮助用户回到 Routine Definition 层修正。

### 15.2 默认 Routine 与当天选择

功能定义：

- weekday default 应自动选择当天 routine，不要求用户每天确认。
- Today 的当前 Routine 入口应提供显式、可理解、低成本的日期级例外选择。
- routine 选择直接决定当天的 block 结构、checklist、note 和 reminder。
- v1 中一个自然日只运行一个 routine。

产品要求：

- 默认 routine 自动运行是产品主路径；显式选择是例外路径。
- 用户应能快速理解不同 routine 的差异。
- 如果今天没有默认或显式选择，App 应明确展示无 routine 状态和选择入口。

### 15.3 Materialized Day

功能定义：

- App 将默认或显式 Daily Routine Selection 物化为当天运行快照。
- 物化结果可供 Now、Today、Widget、Live Activity、App Shortcut 和通知使用。
- 物化结果可以被缓存或持久化，但不能成为 routine 结构权威。
- 当天 checklist 完成状态与物化结构关联保存。

产品要求：

- 物化过程必须可重复、可解释、可从 Routine Definition 重新生成。
- 物化结构在 Today 中只读；Feedback 不得直接写回 Saved Day Type。
- checklist 完成状态不得回写 Routine Definition。

### 15.4 Now：当前运行视图

功能定义：

- 根据当前时刻解析 `activeChain`。
- 展示当前链条中的 note 与 checklist。
- 将未完成 checklist 作为主要焦点。
- 上层已完成时，任务来源自动下沉到更低层。
- 支持快速勾选 checklist。
- 明确表达当前 blank 时段或无行动项的状态。
- 保持信息简短、明确、即时。

产品要求：

- `Now` 应是使用频率最高的页面。
- `Now` 的语言应该像“陪伴你运行这一天”，而不是“提醒你还有很多事没做”。
- `Now` 不能包含结构编辑入口。

### 15.5 Today：只读结构视图

功能定义：

- 以时间轴展示当天结构。
- 展示 base / overlay 的嵌套关系。
- 展示当前时间线。
- 支持查看 block 详情。
- 支持查看 note、checklist 和 reminder。
- 支持完成明确的 checklist item，并从 block 发起 Feedback。

产品要求：

- `Today` 以“查看和理解”为主，不提供结构编辑。
- 任何复杂编排能力都不应出现在 Today。
- Today 中的 block 详情是只读 inspector，只包含 checklist completion、Feedback 与 Done。

### 15.6 Checklist 执行系统

功能定义：

- checklist item 绑定在 Routine Definition 的具体 block 上。
- materialized day 中为每个 checklist item 生成当天执行状态。
- 用户可以快速完成 checklist item。
- checklist 完成后驱动 `taskSourceBlock` 重新计算。

产品要求：

- checklist 的语义必须始终接近“步骤清单”，而不是“事务列表”。
- 一次性、不重复的事项不应鼓励进入系统。
- 移动端不应强调快速新增 checklist item。
- 完成状态只属于当天，不改变 Routine Definition。

### 15.7 Note 系统

功能定义：

- note 来自 Routine Definition。
- note 绑定在 block 上。
- note 在执行上下文中以低于 checklist 的权重显示。
- note 的语义更像固定的自我提示语。

产品要求：

- note 不应演变为长文本笔记系统。
- note 的最佳状态是短、稳定、可重复出现。
- App 不提供当天 note 编辑。

### 15.8 提醒系统

功能定义：

- reminder rule 来自 Routine Definition。
- App 从 materialized day 自动推导提醒计划。
- 支持 block 开始提醒。
- 支持开始前提醒。
- 在通知和系统表面中展示当前状态与下一步。

产品要求：

- 默认提醒风格应尽量温和。
- 提醒应更接近“轻推一下”，而不是“强制中断”。
- Widget、Live Activity、通知、Now 页面应共同构成一个低侵入的提醒体系。
- 通知动作只能执行轻量动作，例如打开当前上下文或完成当前 checklist item。

### 15.9 导入 / 导出

导入导出不是协作功能，而是单人 routine 管理与外部编排接口。

功能定义：

- 导入 Routine Config File。
- 导入前提供摘要预览与校验结果。
- 导入后加入本地 routine library。
- 导出 Routine Config File，方便用户备份、修改或交给外部工具继续编排。

产品要求：

- 导入应服务于外部编排结果落地，而非远程同步。
- 导出应保留 Routine Definition 的结构权威性。
- 当天 checklist 完成状态不应混入 Routine Definition 导出。

### 15.10 外部 AI 编排接口

这是未来产品的重要扩展方向，但必须明确边界。

功能定义：

- 允许云端或 AI 工具生成 Routine Definition 草案。
- 支持这些结果被导入本地。
- 支持在本地预览、校验、确认、应用。

明确边界：

- 不做传统云同步。
- 不做远程数据库作为真相源。
- 不允许远程直接无确认覆盖本地 routine。
- 不允许远程直接修改当天执行状态。
- 云端是“Routine Definition 编排器”，本地是“确认与运行器”。

### 15.11 Widgets

Widget 是 Samoyed “温和陪伴”的关键系统表面。

功能定义：

- 展示当前 block。
- 展示少量 checklist。
- 展示剩余行动项。
- 支持直接完成或切换展示中的 checklist item。
- 点击回到正确上下文。

产品要求：

- Widget 不应像待办小组件那样变成任务板。
- Widget 不提供 routine 结构编辑。
- Widget 不提供新增 checklist 或新增 block。
- Widget 应更像“今天的运行状态窗”。

### 15.12 Live Activities

Live Activity 是“当前这件事正在进行”的持续展示。

功能定义：

- 展示当前 block。
- 展示一个最关键的当前 checklist item。
- 展示剩余数量。
- 提供一个轻量完成动作或打开 App。

产品要求：

- Live Activity 是陪伴式、持续式，不是高刺激式。
- 它应该帮助用户维持当前状态，而不是制造存在感。
- Live Activity 不提供结构编辑或 routine 切换。

### 15.13 App Shortcuts

六个 App Intent 的共同定位是：

- 快速进入当前运行状态
- 快速完成当前 checklist
- 快速打开当前 block

产品要求：

- 所有系统入口都应围绕“现在”展开，而不是围绕“新建”展开。
- 它们服务的是执行，而不是编排。
- 它们不得暴露创建 block、编辑时间、修改 routine、切换结构等能力。

## 16. 明确移除的产品能力

以下能力不属于 Config-first v1：

- 在 Today 中新建 `BaseBlock`
- 在 Today 中新建 `OverlayBlock`
- 在 Today 中编辑 checklist 文本
- 在 Today 中编辑 reminder
- 在 Today 中取消 block
- 在 Today 中通过层级塌缩修正结构
- 在 Today 中拖拽 resize block
- 在 Today 中自由 reparent
- 从今天的临时结构保存为 routine
- 在 App 内从空白创建正式 routine
- 把 checklist 完成状态写回 Routine Definition

这些能力如果未来需要出现，必须作为独立的“Routine Definition authoring”或“routine builder”产品重新定义，不能混入当前运行终端。

没有移动端结构编辑例外。Routine 的任何结构变化都必须来自导入或经用户审批的 Suggestion。

## 17. 信息优先级

Samoyed 的信息优先级应当始终是：

1. 默认正在运行哪一个 routine；今天是否有例外？
2. 我现在在哪种状态里？
3. 我此刻该注意什么？
4. 我此刻还有哪几个 checklist item 没完成？
5. 今天整体结构是什么？
6. 这个结构来自哪份 Routine Definition？
7. 这是当天 checklist 执行，还是需要在 Suggestions 中审批未来版本？

不应把“如何在 App 内编辑它”作为信息层级的一部分。

## 18. 交互风格要求

### 18.1 展示优先

- 首屏优先展示当前运行状态。
- 减少需要思考的入口。
- 不让编辑入口干扰执行心智。

### 18.2 轻量完成优先

- 勾选 checklist 必须很快。
- 进入 App 后应几乎不需要思考就能完成当前动作。
- 系统表面应支持最常用的完成动作。

### 18.3 编排外置

- App 不鼓励用户随时打开手机改日程。
- App 不把“快速输入”当主能力。
- routine 的结构改进发生在 Routine Definition 层。

### 18.4 温和提醒

- 不使用 alarm 式心智作为产品主轴。
- 鼓励通过系统表面“持续可见”来替代“强打断”。

## 19. 成功指标

Samoyed 的成功不应以“新增了多少任务”或“编辑了多少 block”衡量，而应以以下指标衡量：

- 用户是否拥有多个稳定 Routine Definition
- 默认 Day Type 是否可靠自动运行，用户是否只在例外日进行选择
- 用户是否高频使用 `Now`
- 用户是否会通过 `Today` 理解当天结构
- 用户是否在 App 外通过 Widget / Live Activity 完成 checklist
- 用户是否减少了在手机上临时组织生活的负担
- 用户是否感受到提醒是“配合的”，而不是“打断的”
- 用户是否能用外部工具或 AI 生成并迭代 Routine Definition

## 20. 风险

- 如果产品表达不清，用户可能误以为它只是另一个待办 App。
- 如果 App 内编辑入口过重，会背离“Config-first 运行终端”的方向。
- 如果配置文件校验和预览不够清楚，用户会不知道 routine 是否可运行。
- 如果默认自动运行不可靠或例外入口不清楚，用户仍会承担重复确认负担。
- 如果 checklist 看起来像随手任务，会破坏 routine-first 心智。
- 如果提醒做得太强，会违背产品的陪伴式定位。
- 如果云端编排边界不清，会慢慢滑向远程真相和伪同步。
- 如果 completion state 和 Routine Definition 结构混在一起，会破坏“Routine Definition 是结构权威”的核心原则。

## 21. 当前实现与目标方向的关系

### 21.1 仍符合方向的部分

- 单人本地模型
- `Now` 作为执行页
- `Today` 作为时间轴结构页
- 分层 block 与 `taskSourceBlock`
- Widget / Live Activity / App Shortcuts
- 导入导出基础
- 通知动作
- checklist 完成状态

### 21.2 需要收紧或移除的部分

如果当前实现中存在以下能力，它们应被视为旧方向遗留，而不是 Config-first v1 的目标：

- App 内创建 block
- App 内编辑 block
- App 内编辑 checklist 内容
- App 内编辑 note 或 reminder
- Today 中拖拽 resize block 或复杂结构编辑
- Today 中 cancel block
- 从当天结构反向生成可复用 routine
- 把 Today 设计成通用结构编辑器

新的产品方向要求：

- Routine Definition 成为结构权威。
- Library 围绕 Routine Definition 管理。
- Today 完全只读，只保留 checklist completion、Feedback 和现有 Routine 选择。
- Now 和系统表面聚焦执行。
- App 只记录当天 checklist completion 等执行状态。

## 22. 最终产品主张

Samoyed 想提供的不是“更多效率”，也不是“更方便地在手机上改日程”，而是“更少犹豫地运行已经想清楚的一天”。

用户每天不需要在手机上重新规划人生。

用户需要的是：

- 用配置文件沉淀几种稳定生活 routine
- 默认 Day Type 自动运行，例外日再明确选择
- 白天在合适时刻被温和提醒
- 当下知道自己处于什么状态
- 看见那些真正该在那个状态里完成的 checklist
- 完成 checklist，而不破坏 routine 本身
- 在需要改进结构时，回到 Routine Definition 层迭代

如果说别的 App 是帮用户“管理事情”，Samoyed 更像是在帮用户“运行生活”。
