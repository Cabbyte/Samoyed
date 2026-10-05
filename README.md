# Samoyed

Samoyed 是单人 Routine 运行终端，包含 SwiftUI iPhone App、共享 Swift 核心与 Nest HTTP/MCP 服务。本 README 定义领域模型和核心算法；当前产品范围见 PRD。

开发与验证：`swift test`；iOS 使用 Xcode 的 `Samoyed` scheme；Nest 的 Node 24 开发命令见 [nest/README.md](nest/README.md)。发布与代码维护见 [MaintenanceGuide.md](MaintenanceGuide.md)。

文档权威顺序如下：

1. [PRD.md](PRD.md) 定义产品目标、用户、优先级和当前范围。
2. 本文档定义数据模型、约束、解析和持久化语义。
3. [Design.md](Design.md) 定义 UI 如何消费核心语义。
4. 系统入口文档只定义阶段性技术方案，不能扩大 PRD 范围。

如果本文档与代码实现冲突，核心规则以本文档为目标；如果本文档与 PRD 在产品行为或优先级上冲突，以 PRD 为准。

当前产品阶段优先保证：

- 空数据下能够安装 Starter Routine 或导入第一份 Routine Config。
- 有默认模板时自动运行今天，不要求每日重复确认。
- `Now` 稳定回答当前状态、当前步骤和下一状态。
- `Today` 是只读时间线，只允许 checklist completion 与选择已有 Routine。
- 本地数据、时间解析、任务完成和模板实例化可靠。
- Timeline Notes 独立记录与同步；Feedback append-only；Suggestion 必须经本地审批；Planner 可选且默认 disconnected。

导入导出、Widget、Live Activity 和六个 App Intent 是当前合同的一部分；移动端结构 authoring、Controls、通知调度与无授权自动覆盖不在当前范围。UI 只能消费核心层语义，不能反向定义数据模型。

结构算法使用每个本地自然日 `0...1440` 的逻辑分钟轴，不把一天的实际秒数写入 block 结构。Nest 用账号 IANA 时区将墙上时间转换为 instant；DST 重复小时取较早 instant，缺失小时按 gap 前移。Swift `NestTimeResolver` 与 TypeScript 使用共同时间用例验证；时区变更需要显式确认，已开始的计划保留原快照时区。

## 1. 术语表

### 1.1 用户术语与代码术语

- 用户看到的“状态”，在代码中统一称为 `TimeBlock`。
- 用户看到的“任务”，在代码中统一称为 `TaskItem`。
- 用户看到的“模板”，在代码中分为 `SuggestedDayTemplate` 和 `SavedDayTemplate`。

### 1.2 核心术语

- `DayPlan`
  - 一天的完整计划。
  - 一个 `DayPlan` 只对应一个本地自然日。

- `TimeBlock`
  - 一段带时间范围的状态块。
  - `DayPlan` 由多个 `TimeBlock` 组成。
  - `TimeBlock` 可以分层叠加。

- `BaseBlock`
  - `layerIndex == 0` 的 `TimeBlock`。
  - 它们构成一天的底层时间骨架，例如起床、上午、午餐、下午、晚餐、晚上、睡觉。

- `OverlayBlock`
  - `layerIndex > 0` 的 `TimeBlock`。
  - 它必须附着在且只能附着在一个直接下层 `TimeBlock` 上。

- `BlankBaseBlock`
  - 运行时自动生成的特殊底层块。
  - 用来填补用户未定义 `BaseBlock` 的时间空档。
  - 它不持久化，不参与模板保存，也不是用户直接编辑的正式对象。

- `layerIndex`
  - 表示 `TimeBlock` 的层级。
  - 从 `0` 开始。
  - 子块的 `layerIndex` 必须等于父块的 `layerIndex + 1`。

- `parentBlock`
  - 一个 `TimeBlock` 的直接下层块。
  - 只有 `BaseBlock` 没有 `parentBlock`。

- `activeChain`
  - 某一时刻处于生效状态的一条唯一路径。
  - 它从一个 `BaseBlock` 开始，向上经过零个或多个 `OverlayBlock`。
  - 在 `BlankBaseBlock` 补齐之后，任意分钟都必须能得到一条 `activeChain`。

- `activeBlock`
  - 当前时刻 `activeChain` 中层级最高的那个 `TimeBlock`。

- `taskSourceBlock`
  - 当前任务面板应该展示任务的那个 `TimeBlock`。
  - 它不一定等于 `activeBlock`。

- `TimingMode`
  - `TimeBlock` 的时间定义模式。
  - 只有两种：`absolute` 或 `relative`。

- `absolute`
  - 通过当天的绝对时间定义开始时刻。
  - 例如 `12:00` 开始。

- `relative`
  - 通过相对直接下层块开始时刻的偏移定义开始时刻。
  - 例如“从父块开始后 30 分钟开始，持续 60 分钟”。

- `resolvedStart`
  - 算法计算后的实际开始时刻。

- `resolvedEnd`
  - 算法计算后的实际结束时刻。

- `SuggestedDayTemplate`
  - 系统自动从最近三天的 `DayPlan` 生成的候选模板。
  - 会滚动刷新。
  - 不能直接手动创建。

- `SavedDayTemplate`
  - 可从起步模板、导入或已批准的 Routine improvement 得到的正式 Routine。
  - 不会自动滚动删除。
  - iPhone 上只读；批准 Suggestion 时通过新 version 更新并保留 provenance。

- `WeekdayTemplateRule`
  - 一个“星期几 -> 正式模板”的自动选择规则。

- `DateTemplateOverride`
  - 一个“具体某一天 -> 正式模板”的临时覆盖规则。
  - 它的优先级高于 `WeekdayTemplateRule`。

- `DayTemplateSelection`
  - 用户通过“今天不同”等例外入口，对某个具体日期作出的显式选择。
  - 它的优先级高于 `DateTemplateOverride` 和 `WeekdayTemplateRule`。

## 2. 数据模型定义

本文档使用“本地自然日”和“分钟级时间”描述规则。实际实现可以使用 `Date`、`Calendar` 和本地时区，但必须遵守本文档的语义。

### 2.1 `DayPlan`

`DayPlan` 表示某一个本地自然日的完整计划。

建议字段：

- `id`
- `date`
- `sourceSavedTemplateID`
- `lastGeneratedAt`
- `hasUserEdits`
- `blocks: [TimeBlock]`

约束：

- 一个 `DayPlan` 只对应一个本地自然日。
- 同一个自然日最多只有一个有效的 `DayPlan`。
- `sourceSavedTemplateID == nil` 表示该日计划不是由正式模板直接实例化得到，或者实例化来源不可用。
- `hasUserEdits` 只要在落库后发生过一次用户提交的内容修改，就必须为 `true`。
- 纯运行时解析、`BlankBaseBlock` 补齐、缓存刷新都不算用户编辑。

### 2.2 `TimeBlock`

`TimeBlock` 是系统的核心对象。它表示一天中的一个时间块，也就是用户概念中的“状态”。

建议字段：

- `id`
- `dayPlanID`
- `parentBlockID`
- `layerIndex`
- `title`
- `note`
- `reminders: [ReminderRule]`
- `tasks: [TaskItem]`
- `timingMode`
- `absoluteStartMinuteOfDay`
- `requestedEndMinuteOfDay`
- `relativeStartOffsetMinutes`
- `requestedDurationMinutes`
- `resolvedStart`
- `resolvedEnd`
- `isCancelled`

字段语义：

- `parentBlockID`
  - `layerIndex == 0` 时必须为 `nil`。
  - `layerIndex > 0` 时必须指向一个直接下层块。

- `absoluteStartMinuteOfDay`
  - 仅在 `timingMode == absolute` 时有效。
  - 表示相对于当天 `00:00` 的分钟数。

- `requestedEndMinuteOfDay`
  - 仅在 `timingMode == absolute` 时有效。
  - 可选。
  - 表示用户显式请求的结束时间。

- `relativeStartOffsetMinutes`
  - 仅在 `timingMode == relative` 时有效。
  - 表示相对于直接父块开始时刻的偏移分钟数。

- `requestedDurationMinutes`
  - 仅在 `timingMode == relative` 时有效。
  - 可选。
  - 表示用户显式请求的持续时长。

- `resolvedStart` / `resolvedEnd`
  - 运行时计算字段。
  - 由算法生成，不由用户直接填写。
  - 它们不是用户语义上的源数据。
  - 如果存储层为了查询方便持久化它们，也只能把它们当作可失效缓存。
  - 任何读取到的旧缓存都不能跳过重新解析与重新校验。

- `isCancelled`
  - 表示该块已经从有效计划中移除，但可能仍保留历史记录。

补充说明：

- `BlankBaseBlock` 不作为持久化字段单独存储。
- 它在运行时表现为一种特殊的 `TimeBlock` 视图模型。
- 它必须满足：
  - `layerIndex == 0`
  - 没有 `parentBlockID`
  - 没有任务
  - 没有提醒
  - 不能直接作为模板数据写回存储

### 2.3 `TaskItem`

`TaskItem` 是 `TimeBlock` 下的单个 checklist 任务。

建议字段：

- `id`
- `blockID`
- `title`
- `order`
- `isCompleted`
- `completedAt`

约束：

- `TaskItem` 只有 checklist 语义，不包含子任务。
- `TaskItem` 的顺序应保持稳定，以便任务面板可重复呈现。

### 2.4 `ReminderRule`

ReminderRule 保留提醒意图；当前版本不调度系统通知。

建议字段：

- `id`
- `triggerMode`
- `offsetMinutes`

建议语义：

- `triggerMode == atStart`
  - 在块开始时提醒。

- `triggerMode == beforeStart`
  - 在块开始前 `offsetMinutes` 分钟提醒。

补充约束：

- `ReminderRule` 只表达提醒意图，不直接等于某个已调度的系统通知实例。
- 未来通知层必须从“当前有效且已解析的 `DayPlan`”派生提醒计划。
- 任何会影响时间结果的操作，例如创建、编辑、取消、重生成，都必须让该日提醒计划失效并可幂等重建。

### 2.5 `TaskBlueprint`

`TaskBlueprint` 是模板中的单个任务定义。

建议字段：

- `id`
- `title`
- `order`

约束：

- `TaskBlueprint` 只保存模板结构，不保存完成状态。

### 2.6 `BlockTemplate`

`BlockTemplate` 是模板中的单个时间块定义。它与 `TimeBlock` 的结构相似，但不包含运行时状态。

建议字段：

- `id`
- `parentTemplateBlockID`
- `layerIndex`
- `title`
- `note`
- `reminders: [ReminderRule]`
- `taskBlueprints: [TaskBlueprint]`
- `timingMode`
- `absoluteStartMinuteOfDay`
- `requestedEndMinuteOfDay`
- `relativeStartOffsetMinutes`
- `requestedDurationMinutes`

说明：

- `taskBlueprints` 是任务蓝图，只保存任务标题与顺序，不保存完成状态。

### 2.7 `SuggestedDayTemplate`

`SuggestedDayTemplate` 是系统从最近三天自动生成的候选模板。

它是实验性的模板发现能力，不是首次激活的前置条件，也不是当前产品主路径。生产用户即使没有任何历史 `DayPlan`，也可以安装 Starter Routine 或导入第一份 `SavedDayTemplate`。

建议字段：

- `id`
- `sourceDate`
- `sourceDayPlanID`
- `blocks: [BlockTemplate]`

约束：

- 候选模板只来自最近三天。
- 候选模板会随着日期推进而滚动刷新。
- 候选模板不能手动创建。

### 2.8 `SavedDayTemplate`

`SavedDayTemplate` 是可用于生成真实 `DayPlan` 的正式日型模板。

建议字段：

- `id`
- `title`
- `sourceSuggestedTemplateID?`
- `blocks: [BlockTemplate]`
- `createdAt`
- `updatedAt`

约束：

- 正式模板可以来自起步模板、导入、批准的 Suggestion，或保存某个候选模板。
- 只有来源确实是候选模板时才填写 `sourceSuggestedTemplateID`；其他创建来源必须允许它为空，或迁移为等价的来源枚举。
- 首次激活不能依赖最近三天候选模板。
- 正式模板在 iPhone 上只读；结构变化通过导入或经审批的 Suggestion 产生新版本。

### 2.9 `WeekdayTemplateRule`

`WeekdayTemplateRule` 定义某个星期几默认采用哪个正式模板。

建议字段：

- `weekday`
- `savedTemplateID`

约束：

- 同一个 `weekday` 最多只能映射到一个 `SavedDayTemplate`。
- 同一个 `SavedDayTemplate` 可以被多个 `weekday` 引用。

### 2.10 `DateTemplateOverride`

`DateTemplateOverride` 定义某个具体日期临时采用哪个正式模板。

建议字段：

- `date`
- `savedTemplateID`

约束：

- 同一个 `date` 最多只能有一个 override。
- override 只影响对应日期，不自动扩散到其他日期。

### 2.11 `DayTemplateSelection`

`DayTemplateSelection` 记录用户对某个具体日期主动做出的最终选择，包括选择某个正式模板或明确选择无模板日。

建议字段：

- `date`
- `selectedTemplateID`
- `source`
- `selectedAt`

约束：

- 同一日期的最终选择按最新有效记录解析。
- 显式选择只影响对应日期。
- 显式选择用于处理例外，不是每天必须写入的确认记录。

## 3. 结构约束与不变量

以下规则必须始终成立。任何写操作都不能留下违反这些约束的数据。

### 3.1 层级规则

1. `layerIndex` 从 `0` 开始。
2. `BaseBlock` 必须满足 `layerIndex == 0`。
3. `BaseBlock` 没有 `parentBlockID`。
4. `OverlayBlock` 必须满足 `layerIndex > 0`。
5. `OverlayBlock` 必须且只能有一个直接父块。
6. 子块的 `layerIndex` 必须严格等于父块的 `layerIndex + 1`。
7. 不能形成循环父子关系。

### 3.2 重叠规则

1. 同一个父块下、同一层级的两个 `TimeBlock` 不允许时间重叠。
2. 不同层级允许重叠，但必须是明确的父子承载关系。
3. 任一时刻不能存在两个并列的“最上层生效块”。
4. 上层块不能跨越多个下层块。它必须完全落在其直接父块的时间范围之内。
5. 用户定义的 `BaseBlock` 不要求无缝覆盖整天。
6. `BaseBlock` 之间的空档由运行时自动补齐为 `BlankBaseBlock`。

### 3.3 时间模式规则

1. `TimingMode` 只能二选一：`absolute` 或 `relative`。
2. 同一个 `TimeBlock` 不能同时填写两套时间字段。
3. `BaseBlock` 必须使用 `absolute`。
4. `OverlayBlock` 可以使用 `absolute` 或 `relative`。
5. `relative` 模式只能相对于直接父块定义，不能跨层引用祖先块。

### 3.4 任务规则

1. `TaskItem` 只是 checklist 项。
2. `TimeBlock` 可以没有任务。
3. 上层块即使没有任务，也仍然可以存在并保持可见。
4. 任务显示逻辑由 `taskSourceBlock` 决定，而不是简单等同于 `activeBlock`。

### 3.5 模板规则

1. 系统始终维护最近三天的候选模板窗口。
2. “最近三天”在本规格中统一定义为“含今天在内的最近三个本地自然日”，即 `today-2`、`today-1`、`today`。
3. 候选模板会滚动刷新。
4. 正式模板不会因为窗口滚动而自动消失。
5. 正式模板可以从起步模板、导入、批准的 Suggestion 或候选模板生成，但无论来源都必须满足相同约束。

## 4. 时间解析算法

时间解析的目标是为每个 `TimeBlock` 计算 `resolvedStart` 和 `resolvedEnd`。

### 4.0 权威输入与派生结果

1. `TimeBlock` 的权威输入是层级关系、时间模式和原始时间参数。
2. `resolvedStart` / `resolvedEnd` 只是派生结果，不是源事实。
3. 即使持久化层缓存了旧的 `resolvedStart` / `resolvedEnd`，核心层在做校验、任务来源计算和模板导出前，仍然必须基于权威输入重新解析。
4. 任何新解析结果都必须可以完整覆盖旧缓存。

### 4.1 总体原则

结束时间的“优先级”在实现上应理解为“结束上界的裁剪顺序”。也就是说，`resolvedEnd` 本质上等于所有有效结束上界中的最早时刻。

对任意 `TimeBlock`，候选结束上界可能包括：

- 直接父块的 `resolvedEnd`
- 同父同层下一个块的 `resolvedStart`
- 自身显式请求的结束时刻
- 当天 `24:00`

最终 `resolvedEnd` 必须取这些上界中的最早值。

### 4.2 `BaseBlock` 的解析规则

1. `resolvedStart = date 00:00 + absoluteStartMinuteOfDay`
2. `BaseBlock` 的候选结束上界包括：
   - 下一个 `BaseBlock` 的 `resolvedStart`
   - 自身的 `requestedEndMinuteOfDay`
   - 当天 `24:00`
3. `resolvedEnd` 取以上有效上界中的最早时刻。
4. 如果没有下一个 `BaseBlock`，则默认用当天 `24:00` 作为结束上界。
5. 如果用户填写的结束时间晚于其他上界，则必须被截断。
6. 用户定义的 `BaseBlock` 不要求首尾相连，空档允许存在。

### 4.3 `OverlayBlock` 的解析规则

1. 先解析其直接父块。
2. `timingMode == absolute` 时：
   - `resolvedStart = date 00:00 + absoluteStartMinuteOfDay`
3. `timingMode == relative` 时：
   - `resolvedStart = parent.resolvedStart + relativeStartOffsetMinutes`
4. `OverlayBlock` 的候选结束上界包括：
   - `parent.resolvedEnd`
   - 同父同层下一个块的 `resolvedStart`
   - 自身显式请求的结束时刻
5. `timingMode == relative` 且存在 `requestedDurationMinutes` 时：
   - 自身显式请求的结束时刻为 `resolvedStart + requestedDurationMinutes`
6. `timingMode == absolute` 且存在 `requestedEndMinuteOfDay` 时：
   - 自身显式请求的结束时刻为 `date 00:00 + requestedEndMinuteOfDay`
7. `resolvedEnd` 取以上有效上界中的最早时刻。
8. 如果自身请求的持续时长超过父块结束时刻，则必须截断。

### 4.4 非法时间的判定

以下情况必须被视为非法：

- `resolvedStart >= resolvedEnd`
- `OverlayBlock` 的 `resolvedStart` 不在父块时间范围内
- `OverlayBlock` 的 `resolvedEnd` 超出父块时间范围
- 同父同层块解析后发生时间重叠
- `BaseBlock` 解析后越过当天 `24:00`

### 4.5 解析顺序

建议解析顺序：

1. 先解析所有 `BaseBlock`
2. 再按 `layerIndex` 从低到高解析 `OverlayBlock`
3. 同一父块下的同层块按开始时刻排序
4. 每次编辑后，对受影响的父块分支重新解析

### 4.6 `BlankBaseBlock` 补齐算法

在所有用户定义的 `BaseBlock` 完成解析后，系统必须执行一次运行时补齐。

规则：

1. 只检查 `layerIndex == 0` 的用户定义块
2. 检查以下三类空档：
   - 当天 `00:00` 到第一个 `BaseBlock` 开始之间
   - 相邻两个 `BaseBlock` 之间
   - 最后一个 `BaseBlock` 结束到当天 `24:00` 之间
3. 每个空档都生成一个运行时 `BlankBaseBlock`
4. `BlankBaseBlock` 只存在于运行时解析结果中，不写入持久化层
5. `BlankBaseBlock` 不包含任务、备注、提醒或模板身份
6. `BlankBaseBlock` 不参与候选模板生成，也不参与正式模板保存
7. `BlankBaseBlock` 不能直接成为新 `OverlayBlock` 的持久化父块
8. 如果用户在空白时段发起编辑，UI 应先将该空档转为真实 `BaseBlock`，然后再继续后续操作
9. 从空白时段创建真实 `BaseBlock` 时，编辑器的默认开始和结束时间应初始化为该空档边界
10. 如果新建的真实 `BaseBlock` 只占用原空档的一部分，则剩余未占用区间继续在运行时表现为 `BlankBaseBlock`
11. 用户不能直接在 `BlankBaseBlock` 上持久化创建 `OverlayBlock`；必须先把该时段转为真实 `BaseBlock`

## 5. 取消与层级塌缩算法

本节是核心变更算法与兼容测试的技术规格，不为 Today 提供 cancel/编辑入口。

当一个下层块被取消时，它上方的块需要整体下沉一层。

### 5.1 `cancelBlock(blockID)` 的语义

1. 被取消的块本身不再参与有效计划计算。
2. 被取消块的直接子块会被重新挂到“被取消块的父块”之下。
3. 这些直接子块以及它们的全部后代，`layerIndex` 都需要减 `1`。

### 5.2 时间保持原则

取消操作不应让仍然存活的块在时间上发生意外漂移。优先原则如下：

1. 尽量保持存活块取消前的 `resolvedStart` / `resolvedEnd` 不变。
2. 因此，被重新挂接的“直接子块”需要先把自己当前的已解析时间固化为绝对时间：
   - 新的 `timingMode = absolute`
   - 新的 `absoluteStartMinuteOfDay = 取消前 resolvedStart 对应的 minute-of-day`
   - 新的 `requestedEndMinuteOfDay = 取消前 resolvedEnd 对应的 minute-of-day`
3. 直接子块的后代不需要改写与其直接父块之间的关系，只需整体把 `layerIndex` 同步减 `1`。

### 5.3 取消后的校验

取消完成后，必须重新解析并校验该分支。

如果取消导致以下任一问题，则操作必须失败并回滚：

- 同父同层出现时间重叠
- 某个子块不再落在其父块范围内
- 解析后出现 `resolvedStart >= resolvedEnd`

## 6. 当前块与任务面板算法

### 6.1 `activeChain`

对某个时刻 `t`：

1. 找出所有满足 `resolvedStart <= t < resolvedEnd` 且未取消的 `TimeBlock`
2. 这些块必须构成一条唯一的父子链
3. 这条链就是 `activeChain`
4. 在 `BlankBaseBlock` 补齐之后，对任意 `0 <= t < 1440`，`activeChain` 都必须存在

### 6.2 `activeBlock`

- `activeBlock` 是 `activeChain` 中 `layerIndex` 最大的块。
- 它表示当前时刻最上层正在生效的块。

### 6.3 `taskSourceBlock`

`taskSourceBlock` 的计算规则如下：

1. 从 `activeChain` 的最高层开始向下搜索
2. 找到第一个“存在未完成任务”的块
3. 该块就是 `taskSourceBlock`
4. 如果最高层块的任务全部完成，则任务面板切换到下一层
5. 即使任务面板已经切到下层，原来的高层块仍然保持可见
6. 如果整条 `activeChain` 都没有未完成任务，则 `taskSourceBlock = nil`

这条规则保证：

- 不会出现同一时刻两个最上层任务面板竞争
- 只会有一个任务来源块
- 上层可见性和任务面板来源是两个不同概念

## 7. 候选模板生成算法

本节描述已存在的实验能力。候选模板当前处于产品冻结状态：可以保留算法和测试，但不得作为首次激活、默认运行或模板创建的唯一入口。

### 7.1 候选模板窗口

系统始终维护最近三天的候选模板窗口：

- `today-2`
- `today-1`
- `today`

每一天最多对应一个 `SuggestedDayTemplate`。

### 7.2 候选模板生成规则

1. 每个候选模板都来源于对应日期的 `DayPlan`
2. 候选模板保存的是结构快照，而不是运行时对象引用
3. 候选模板中保留：
   - 块的层级结构
   - 时间定义
   - 标题
   - 备注
   - 提醒规则
   - 任务蓝图
4. 候选模板中不保留：
   - 任务完成状态
   - 运行时解析缓存
   - 临时 UI 状态
   - `BlankBaseBlock`
   - 已取消块
5. 如果某一天没有任何用户定义且未取消的块，则该日期不生成候选模板

### 7.3 滚动刷新规则

1. 当本地日期进入新的一天时，候选模板窗口向前滚动一天
2. 超出窗口的旧候选模板自动移除
3. 进入窗口的新日期对应的候选模板自动生成
4. 候选模板不是永久数据

### 7.4 候选模板的刷新与冻结

1. `today-2` 和 `today-1` 的候选模板在窗口内应表现为稳定快照。
2. 如果窗口内某一天的 `DayPlan` 发生一次已提交且成功的修改，则该日期对应的候选模板应整体替换为新的快照。
3. `today` 的候选模板不得随着表单草稿输入实时漂移；只有在一次编辑真正提交成功后才允许刷新。
4. 用户点击“保存为正式模板”时，保存的必须是当前已冻结展示的那一版候选模板快照。

## 8. 正式 Routine 安装、保存与版本规则

### 8.0 安装正式 Routine

生产用户必须能在没有历史计划和候选模板时获得第一个 `SavedDayTemplate`。允许的来源包括：

1. 复制内置起步模板后由用户确认
2. 导入结构化 Routine Config 后由用户确认
3. 从 `SuggestedDayTemplate` 保存（若该实验入口启用）
4. 批准一个经过本地校验的 Routine improvement Suggestion

无论来源如何，正式模板都必须经过同一套结构与时间约束校验。

### 8.1 保存候选模板

用户可以将一个 `SuggestedDayTemplate` 保存为 `SavedDayTemplate`。

保存动作的语义是“复制”，而不是“引用”：

1. 复制模板结构
2. 复制块定义
3. 复制任务蓝图
4. 生成新的正式模板标识

保存完成后：

- 候选模板仍然保持候选模板身份
- 正式模板成为独立对象
- 后续批准新的 Routine version 不会反向修改候选模板

### 8.2 正式 Routine 版本

iPhone 不暴露标题、块结构、时间、备注、提醒或任务蓝图的编辑器。本地结构变更来自导入或 `routineImprovement` Suggestion；Nest 账号还可接收授权的外部编排版本，遵守第 14 节的生效日期和快照保护规则。本地接受后保持稳定的 logical Routine ID，递增 revision，生成新的 `versionID`，记录 `parentVersionID` 与 provenance，并保存旧 revision snapshot。已经物化的 Today 不随之改变。

## 9. 模板选择算法

### 9.1 自动选择

某一日期在没有显式例外时默认采用哪个正式模板，由 `WeekdayTemplateRule` 决定。存在有效默认值时，系统直接运行今天，不要求用户每日确认。

规则：

1. 先取该日期对应的 `weekday`
2. 查询是否存在该 `weekday` 的模板规则
3. 如果存在，则返回对应的 `SavedDayTemplate`
4. 如果不存在，则默认不选中任何模板

### 9.2 临时覆盖

某个具体日期可以通过 `DateTemplateOverride` 临时指定模板。

规则：

1. 如果某个日期存在 override，则直接使用 override 指向的正式模板
2. override 的优先级高于所有 `WeekdayTemplateRule`
3. override 只影响该具体日期

用户从“今天不同”入口主动切换模板时，应记录 `DayTemplateSelection`。这个显式选择代表用户对当天的最终决定，优先级高于预先配置的 date override 与 weekday default。

### 9.3 最终优先级

对任意日期 `d`，最终模板选择顺序必须为：

1. `DayTemplateSelection`
2. `DateTemplateOverride`
3. `WeekdayTemplateRule`
4. 无模板

这里的“显式”表示用户主动处理例外，而不是每天必须完成一次模板选择。

### 9.4 `DayPlan` 落库生成时机

未来某一天 `d` 的 `DayPlan` 不是纯运行时临时值，而是需要预先落库生成的正式数据。

规则：

1. 首选策略是在 `d-1` 晚上或 `d` 日零点主动生成 `DayPlan(d)` 并落库
2. 如果上述主动生成没有发生，则第一次读取或编辑该日期前，系统必须同步执行一次 `ensureMaterialized(d)`
3. `ensureMaterialized(d)` 必须是幂等的
4. 对同一个自然日，若已经存在有效 `DayPlan` 且调用方没有显式请求重生成，则 `ensureMaterialized(d)` 只能返回现有计划，不能重复创建第二份
5. 实现上必须使用“按日期唯一”约束或等价事务语义，防止并发触发时生成重复记录
6. 生成时按以下顺序确定模板：
   - `DayTemplateSelection`
   - `DateTemplateOverride`
   - `WeekdayTemplateRule`
   - 无模板
7. 如果最终没有选中任何模板，也必须为该日期落库一个空的 `DayPlan`
8. 这个空 `DayPlan` 运行时仍会通过 `BlankBaseBlock` 补齐全天
9. 一旦 `DayPlan(d)` 已经落库，它就是一个快照
10. 后续对 `SavedDayTemplate`、weekday 规则或 override 的修改，不会自动回写已落库的 `DayPlan`
11. 自动预生成和首次访问补生成都绝不能隐式覆盖已有 `DayPlan`

### 9.5 显式重生成规则

如需让模板变更影响某个已经落库但尚未真正使用的未来日期，必须走显式重生成，而不是复用普通生成。

规则：

1. 当前阶段只允许对“严格晚于 today 的未来日期”执行重生成。
2. `today` 与所有过去日期都禁止重生成。
3. 只有当目标 `DayPlan` 满足以下条件时才允许重生成：
   - `hasUserEdits == false`
   - 不存在任何已完成任务
4. 重生成必须原子性替换该日原有的块与任务快照。
5. 重生成时重新执行模板选择优先级：
   - `DayTemplateSelection`
   - `DateTemplateOverride`
   - `WeekdayTemplateRule`
   - 无模板
6. 如果不满足重生成条件，操作必须失败，而不是静默覆盖用户已有内容。
7. 自动预生成、首次访问补生成都不得被视为重生成。

## 10. 从模板生成 `DayPlan` 的算法

### 10.1 生成来源

只有 `SavedDayTemplate` 可以用于正式生成某一天的 `DayPlan`。

### 10.2 生成步骤

1. 复制模板中的所有 `BlockTemplate`
2. 生成对应的 `TimeBlock`
3. 复制任务蓝图，生成新的 `TaskItem`
4. 将所有任务的 `isCompleted` 初始化为 `false`
5. 解析整天的时间
6. 校验结构约束与时间约束
7. 只有全部成功时才提交生成结果

### 10.3 失败语义

如果模板实例化后违反任何约束，则生成操作必须原子性失败，不允许留下半生成数据。

### 10.4 模板与已落库 `DayPlan` 的关系

`SavedDayTemplate` 与已落库 `DayPlan` 必须是“复制快照”关系，而不是“动态引用”关系。

这意味着：

1. 模板被编辑后，不自动修改已经存在的 `DayPlan`
2. 已落库的 `DayPlan` 可以继续被用户单独编辑
3. 候选模板依然来源于真实 `DayPlan`，而不是反向来源于正式模板
4. 未来日期若要吸收模板变化，只能通过满足 9.5 条件的显式重生成

## 11. App 状态与入口

界面合同集中在 [Design.md](Design.md)，不再在领域规格中维护另一套 Today 编辑器和模板管理 UI。

### 11.1 当前分层

- `SamoyedStore` 负责加载、物化、持久化、用户命令与同步触发。
- `SamoyedPresentation` 把核心数据映射成 Now、Today、Routine/Library 的 screen model。
- `SamoyedDocumentRepository` 和 `NestLocalDatabase` 为 App 与扩展提供 App Group SQLite、账号分区及原子写入。
- `NestAccountController` 负责认证生命周期和同步；Nest 服务的 domain/repository 分别负责规则和 revision/receipt/cursor。
- 视图仅持有日期选择、详情、草稿等 presentation state，不缓存另一套时间或模板推导结果。

### 11.2 运行界面边界

Now 展示当前执行上下文。Today 展示只读计划、checklist 与独立 Timeline Notes；日期返回和 Routine 标题以实际显示的快照为准。Library 组织 Routines、Usual Week、配置文件、Nest、Suggestions、Planner 和显示设置。

导入、Suggestion 审批、授权的 Nest 编排与 Today 的查看/完成是不同写入入口。每个入口仍必须经过对应领域校验；不能因为核心层有结构修改算法，就恢复手机端 block 编辑器。

### 11.3 Routine Config Deeplink 导入

外部编排器优先通过无服务器的内嵌 deep link 打开确认式导入流程：

```text
samoyed://import-routine?v=1&payload=<unpadded-base64url-utf8-yaml>&title=<percent-encoded-title>
```

已有 HTTPS 托管时仍可使用远程兼容形式：

```text
samoyed://import-routine?url=<percent-encoded-https-url>&title=<percent-encoded-title>
```

规则：

1. `payload` 与 `url` 必须且只能出现一个，`title` 可选。
2. `v=1` 使用 UTF-8 YAML 的无填充 Base64URL 编码，解码后不超过 32 KB。
3. 远程模式下正式构建只接受 HTTPS；Debug 构建额外接受 localhost / `127.0.0.1` / `::1` HTTP。
4. 远程模式只接受成功响应和不超过 512 KB 的 UTF-8 文本；重定向后的最终 URL 仍需通过传输校验。
5. 两种传输都必须先通过 `SamoyedPortableDayBlocks` 的结构与时间校验，再展示来源、block 和 checklist 摘要。
6. deep link 不直接写入数据；用户必须在 App 内确认 Import、Replace 或 Keep Both。
7. 导入只写 Routine Library，不直接修改当天 Materialized Day 或 Execution State；Nest 分区中的写入通过账号同步发送，配置 URL 自身不建立订阅。

## 12. 当前 UI 与平台合同

当前范围包括首次激活、默认自动运行、Now、只读 Today、Timeline Notes、配置导入导出、Usual Week、Nest 账号同步、Feedback、Suggestions、可选 Planner，以及 Home/Accessory Widgets、Live Activity、Dynamic Island 和六个 App Shortcuts。

手机端结构编辑器、Control Widgets、Home Screen Quick Actions、通知调度及无人审批的 Planner 写入不在范围内。候选模板、层级塌缩等内部算法保留不代表它们拥有生产 UI 入口。共享旧字段、历史数据迁移和旧 deep link source 的兼容值继续保留。

## 13. 单元测试要求

以下规则必须由单元测试覆盖：

### 13.1 结构校验测试

- `layerIndex` 与父子关系一致
- `BaseBlock` 没有父块
- `OverlayBlock` 必须有父块
- 不能形成循环
- 同父同层不能重叠

### 13.2 时间解析测试

- `BaseBlock` 正常按下一个同层块结束
- `BaseBlock` 在没有下一个块时按 `24:00` 结束
- `OverlayBlock` 的 `relative` 起点正确
- `requestedDurationMinutes` 会被父块结束时刻截断
- `requestedEndMinuteOfDay` 会被下一个同层块截断
- 非法时间会被拒绝
- 持久化层中的旧 `resolvedStart` / `resolvedEnd` 缓存不会覆盖一次新的合法解析结果

### 13.3 取消与塌缩测试

- 取消中间层后，子块整体下沉一层
- 下沉后时间保持稳定
- 下沉后重新校验不变量
- 非法塌缩会被回滚

### 13.4 任务来源测试

- 当前时刻能正确算出唯一 `activeChain`
- 当前时刻能正确找出 `activeBlock`
- 上层任务未完成时，`taskSourceBlock == activeBlock`
- 上层任务全部完成时，任务面板正确回退到下一层
- 整条链都无未完成任务时，`taskSourceBlock == nil`

### 13.5 模板测试

- 最近三天候选模板窗口滚动正确
- `today` 的候选模板只会在一次编辑成功提交后刷新，不会跟随草稿输入漂移
- 候选模板保存为正式模板时是复制而不是引用
- 正式模板编辑不影响候选模板
- `DateTemplateOverride` 的优先级高于 `WeekdayTemplateRule`
- `DayTemplateSelection` 的优先级高于 `DateTemplateOverride` 与 `WeekdayTemplateRule`
- 存在 weekday default 时可以自动生成今天，不要求每日显式选择
- 无历史计划和候选模板时仍能创建第一个 `SavedDayTemplate`
- 正式模板实例化 `DayPlan` 时，任务完成状态会被重置
- `ensureMaterialized(d)` 在错过预生成时仍能于首次访问补生成
- `ensureMaterialized(d)` 对同一天是幂等的，不会重复生成多个 `DayPlan`
- 显式重生成只允许作用于未被用户修改的未来 `DayPlan`
- `BlankBaseBlock` 能正确补齐底层空档
- `BlankBaseBlock` 不会进入候选模板
- 已落库 `DayPlan` 不会被后续模板编辑自动改写

## 14. Samoyed Nest 与快照保护

本地模式以本地文档运行；连接 Nest 后，`https://samoyed.protium.top` 是账号数据的唯一可写服务，手机保存可离线运行的分账号副本和待发送操作。旧 Sites 只读。App Store 和公共插件目录提交不属于这次 private beta 发布。

### 14.1 版本与时间

- Routine 和星期规则默认从账号时区明天生效；日期例外明确指定目标日。
- 缓存包含有效版本历史与账号游标，缺失日期按该日有效版本物化。
- 既有计划优先保留完整的已开始、已执行或已修正子树；合并后校验结构和保存范围。
- 若新 Routine 会截短或破坏受保护子树，继续使用此前有效快照及其来源，不改写用户请求的规则。
- `offlinePlan` 依据已发出的历史 cursor 验证来源；`legacyPlan` 只用于明确的旧数据导入。执行事件继续引用原来的计划版本、block 和 task instance。

### 14.2 Notes、同步和恢复

- 固定提示语的 wire 字段 `note` 保留；`TimelineNote` 是另一类带 `occurredAt`、时区和可选 block instance 关联的实体。
- 本地 SQLite 同一事务持久化业务状态和 outbox；游标只在页面应用成功后推进。
- 超时重试复用完全相同的 operation ID、payload 与 expected revision。冲突保留双方内容，删除以 tombstone 同步。
- 无效日程恢复需先在一致性备份上演练，再追加有 revision 检查的新计划版本；保留历史、执行事件与 Notes，不覆盖整个数据库。
- 本地 JSON → SQLite 迁移、旧字段解码及账号分区保持兼容；cleanup 不删除已有数据。

实现、运行与证据分别见 [Nest README](nest/README.md)、[状态记录](docs/samoyed-nest-status.md) 和 [运维手册](docs/samoyed-nest-operations.md)。
