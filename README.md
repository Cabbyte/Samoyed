# Samoyed Specification

本 README 是 Samoyed 的领域模型与核心算法规格。

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
- Feedback append-only；Suggestion 必须经本地审批；Planner 可选且默认 disconnected。

导入导出、Widget、Live Activity 和六个 App Intent 是当前合同的一部分；移动端结构 authoring、Controls 与远程自动覆盖仍冻结。UI 只能消费核心层语义，不能反向定义数据模型。

当前阶段对时间采用一个刻意简化的前提：

- 每个本地自然日都按固定 `1440` 分钟处理
- 当前不考虑 DST、夏令时切换、重复小时或缺失小时
- 当前不讨论跨时区同步

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

提醒当前只定义数据，不要求本阶段实现通知调度。

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

iPhone 不暴露标题、块结构、时间、备注、提醒或任务蓝图的编辑器。结构变更来自导入或 `routineImprovement` Suggestion；接受后保持稳定的 logical Routine ID，递增 revision，生成新的 `versionID`，记录 `parentVersionID` 与 provenance，并保存旧 revision snapshot。已经物化的 Today 不随之改变。

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

## 11. UI 实现方案

本节定义未来 iOS App 的完整 UI 方案。它是实现设计，不是当前阶段的编码目标。

### 11.1 UI 总体原则

1. 整个 App 必须以 `SamoyedCore` 为唯一业务核心。
2. SwiftUI 视图层只能读取和提交意图，不能自行计算时间、层级、模板选择或任务来源规则。
3. 所有 `resolvedStart`、`resolvedEnd`、`activeChain`、`taskSourceBlock`、模板选择结果都必须来自核心层。
4. 所有编辑动作在提交前都必须经过核心层校验；UI 不得绕过核心规则直接写入非法数据。
5. 当前阶段先保留 iPhone 单窗口结构，不扩展多窗口和 Widget。

### 11.2 根导航结构

根视图采用 `TabView`，固定包含 3 个一级页面：

1. `NowView`
2. `TodayView`
3. `LibraryView`

每个 Tab 内部可以独立使用 `NavigationStack`。

推荐顺序：

1. `Now`
2. `Today`
3. `Library`

推荐含义：

- `NowView`
  - 面向“此刻应该做什么”。

- `TodayView`
  - 面向“今天整天的时间块结构与编辑”。

- `LibraryView`
  - 面向“规划资产入口”，其中包含 `TemplatesView` 和当天 block 的 YAML 导入导出。

### 11.3 UI 与核心层的边界

未来 UI 需要有一个薄适配层，负责：

- 从本地持久化层读取原始数据
- 组装为 `SamoyedCore` 所需的数据结构
- 调用核心算法
- 将用户编辑意图转换为核心层操作
- 在核心层校验成功后再写回持久化层

UI 不负责：

- 时间解析
- 任务来源回退
- 层级塌缩
- 候选模板窗口滚动
- override 优先级判断

### 11.4 `NowView`

`NowView` 是产品核心、默认首页，也是用户打开 App 后最先需要看到的内容。它优先回答：现在是什么、现在要做什么、接下来是什么。

如果用户尚未拥有可运行模板，`NowView` 应进入真实首次激活流程；不得用生产 sample data 伪造已完成设置的状态。如果今天已有默认模板，则自动运行，不先展示每日模板选择器。

#### 11.4.1 数据来源

`NowView` 必须从核心层拿到：

- 今天的 `DayPlan`
- 当前时刻的 `activeChain`
- 当前时刻的 `activeBlock`
- 当前时刻的 `taskSourceBlock`

#### 11.4.2 页面结构

页面建议从上到下分为以下区域：

1. 当前 block、时间范围与状态说明
2. 当前未完成 checklist，首屏优先展示最多 3 项
3. 下一 block 的轻量预告
4. “今天不同”与查看 `Today` 的次要入口

#### 11.4.3 当前生效链展示

`activeChain` 是核心层推导语义，不是必须完整暴露给用户的产品概念。页面需要表达当前来源与必要上下文，但不应把层级结构本身变成首屏主角。

推荐表现：

- `activeBlock` 视觉上最突出。
- 只有在任务来自下层 block 时，才补充必要的来源说明。
- 不显示 `L0`、`L1`、`taskSourceBlock` 等内部术语。
- 已完成内容折叠或降权，不占据主要首屏空间。

#### 11.4.4 当前任务面板

任务面板只显示 `taskSourceBlock` 的任务，而不是简单显示 `activeBlock` 的任务。

必须遵守：

1. 如果 `taskSourceBlock` 存在，则优先展示该块未完成任务，首屏默认最多 3 项
2. 如果 `taskSourceBlock == nil` 且当前 `activeBlock` 是 `BlankBaseBlock`，则展示“当前为空白时段”
3. 如果 `taskSourceBlock == nil` 且当前 `activeBlock` 不是 `BlankBaseBlock`，则展示“当前链条没有未完成任务”
4. 用户勾选任务后，UI 必须重新向核心层请求新的 `taskSourceBlock`

#### 11.4.5 `NowView` 可执行操作

允许：

- 勾选当前任务
- 查看必要的当前上下文
- 跳转到 `TodayView` 并定位到当前块
- 从“今天不同”切换当天模板或选择无模板日

不建议在 `NowView` 直接做复杂结构编辑，例如：

- 新建底层块
- 调整层级
- 批量编辑时间

这些操作应交给 `TodayView`。

### 11.5 `TodayView`

`TodayView` 是整天结构的只读查看器。它展示今天的 `DayPlan`，只保留 checklist completion、Feedback 和选择已有 Routine。

#### 11.5.1 视觉模型

`TodayView` 应采用“类日历的时间轴视图”，而不是简单列表。

推荐表现：

- 纵向时间轴，覆盖当天 `00:00` 到 `24:00`
- `BaseBlock` 作为主时间轨道
- `OverlayBlock` 在其父块之上显示
- 不同层级通过缩进、层叠卡片、边框或色带区分
- 当前时间应有清晰的“现在”指示线

#### 11.5.2 展示规则

1. `BaseBlock` 必须形成一天的底层骨架
2. `BlankBaseBlock` 需要以低视觉权重补齐所有底层空档
3. `OverlayBlock` 只能显示在其父块内部
4. 同父同层不允许视觉重叠，因为数据上也不允许重叠
5. 被取消的块默认不在主时间轴中展示
6. 如需历史能力，可在未来单独加“已取消”区域，但不属于当前阶段

#### 11.5.3 选中状态

`TodayView` 需要支持“当前选中块”的概念。

选中后应展示：

- 标题
- 层级
- 时间定义方式
- 实际解析时间
- 备注
- 提醒配置
- 任务列表
- 所属父块
- 直接子块列表

#### 11.5.4 新建操作

核心层可以支持以下结构操作，但 P0 UI 不把它们全部作为高频入口。`TodayView` 只在用户明确进入修正流程后发起编辑。

允许新建：

1. 新的 `BaseBlock`
2. 选中某个块后，在其上方新建 `OverlayBlock`

新建时 UI 需要先要求用户选择：

- 标题
- 时间模式：`absolute` 或 `relative`
- 对应时间参数
- 备注
- 提醒
- checklist 任务

但真正是否合法，必须由核心层最终裁定。

#### 11.5.5 编辑操作

`TodayView` 允许编辑：

- 标题
- 备注
- 提醒
- 任务内容
- 时间模式与时间参数

当前阶段不允许自由编辑“父子关系”本身。

当前阶段允许的结构变化仅包括：

1. 新建一个新的 `BaseBlock`
2. 在选中块上新建一个新的 `OverlayBlock`
3. 取消一个已有块并触发层级塌缩

如果未来需要支持显式 reparent，必须先为其补充独立算法规格，再允许进入 UI。

#### 11.5.6 取消操作

`TodayView` 必须提供“取消块”操作，而不是直接删除块。

用户触发取消后：

1. UI 只提交“取消这个 block”的意图
2. 核心层执行层级塌缩与时间固化
3. UI 刷新整个受影响分支

#### 11.5.7 `TodayView` 的辅助视图

推荐包含以下辅助区域：

- 顶部日期切换条
- 当前时间快速定位按钮
- 选中块详情抽屉或底部面板
- 新建/编辑 block 的 sheet
- 仅展示校验失败信息的错误提示层

### 11.6 `TemplatesView`

`TemplatesView` 是低频基础设施页面，负责正式模板和简单默认日设置。候选模板、复杂 schedule 与 date override 管理属于冻结能力，不得进入首次激活或日常启动主路径。

#### 11.6.1 页面结构

目标状态优先拆分为 2 个区域：

1. `Saved`
2. `Defaults`

`Suggested` 可以保留为实验性低优先区域。首次激活必须提供起步模板或导入入口，不能要求用户先积累三天计划。

#### 11.6.2 `Suggested`

该区域展示最近三天的候选模板窗口。

必须展示：

- `today-2`
- `today-1`
- `today`

每个候选模板卡片应包含：

- 来源日期
- 底层块数量
- 总块数量
- 任务蓝图数量
- 预览摘要
- “保存为正式模板”入口

#### 11.6.3 `Saved`

该区域展示所有 `SavedDayTemplate`。

每个正式模板应支持：

- 查看结构预览
- 查看版本与 provenance
- 选择为 Today 或 Usual Week 的现有 Routine
- 请求 Planner 生成改进 Suggestion

必须支持从起步模板或导入得到正式模板；从候选模板保存只是可选来源。

#### 11.6.4 `Schedule`

该区域负责低频默认日设置。当前产品行为是“存在明确默认时自动运行；今天不同时再主动切换”，不要求用户每天进入此页面确认。

以下完整 schedule UI 属于冻结能力；保留这些语义是为了兼容已有数据和实现，不表示它属于 P0 主路径。

它需要同时展示两层信息：

1. `WeekdayTemplateRule`
2. `DateTemplateOverride`

针对明天，页面需要明确展示：

- 明天的日期
- 明天的 weekday
- 由 weekday 规则自动推导出的模板
- 是否存在日期级 override
- 最终生效的模板

#### 11.6.5 明日 override 交互

用户可以在 `TemplatesView` 中为明天设置临时 override。

交互要求：

1. 如果没有 override，则展示“使用 weekday 自动规则”
2. 用户可以从正式模板列表中选一个作为明日 override
3. 如果已经存在 override，用户可以修改或清除
4. 页面必须明确告诉用户：override 优先于 weekday 规则

### 11.7 详情页与审批界面的组织方式

移动端收敛为只读 Routine Detail、Block Details、Feedback sheet、Suggestions pushed navigation 和 Usual Week 的现有 Routine 选择器。结构编辑器不是 iOS 产品合同的一部分。

### 11.8 UI 状态管理

UI 层建议只保留以下几类本地状态：

- 当前选中日期
- 当前选中 block
- 当前打开的只读详情或审批页面
- Feedback 输入草稿
- 提示信息与错误展示状态
- 当前运行时可见的 `BlankBaseBlock` 映射

UI 层不应长期缓存：

- 解析后的 `resolvedStart` / `resolvedEnd`
- 当前活动链推导结果
- 模板最终选择结果

这些必须随时从核心层重新计算。

### 11.9 当前 UI 架构

当前仓库已经统一围绕以下概念构建：

- `SamoyedDocument`
- `DayPlan`
- `TimeBlock`
- `TaskItem`
- `SuggestedDayTemplate`
- `SavedDayTemplate`
- `WeekdayTemplateRule`
- `DateTemplateOverride`
- `DayTemplateSelection`

UI 分层原则：

1. `SamoyedStore` 负责文档加载、物化、持久化和用户命令。
2. `SamoyedPresentation` 负责把核心模型映射成 `Now`、`Today`、`Templates` 所需的 screen model。
3. root view 只负责页面级状态、导航和 sheet，不重复实现核心推导。

### 11.10 当前模型约束

为了保持架构稳定，当前实现应继续遵守以下约束：

1. `DayPlan` 与模板集合是唯一业务真相来源，UI 不维护并行状态副本。
2. `BlankBaseBlock`、active chain、detail model、template summary 都必须在核心层或 presentation 层临时推导，而不是被 UI 长期缓存。
3. root view 可以持有局部 presentation state，例如选中的分段、当前 sheet、编辑草稿，但不直接承担规则计算。
4. 对未来日期的模板变更只影响重新物化或显式 regenerate 的 day plan；已经存在的日计划继续作为快照保留。

### 11.11 Routine Config Deeplink 导入

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
7. 导入只加入本地 Routine Library，不修改当天 Materialized Day 或 Execution State，也不建立持续同步。

## 12. 当前 UI 与平台合同

当前代码已经包含 App UI 与多种系统入口。本节定义产品开发优先级，而不是描述代码是否存在。

Frozen 合同包含：

- 空数据首次激活
- 默认模板自动运行
- `Now` 核心执行体验
- `Today` 只读查看、checklist completion 与现有 Routine 选择
- Starter Routine、Routine 导入、切换与本地持久化
- Feedback、Suggestions 与诚实的 Planner 状态
- Home/Accessory Widgets、Live Activity、Dynamic Island 与六个 App Intents

以下能力仍处于冻结状态：

- 复杂模板候选和 schedule 管理
- 多层时间轴编排的继续扩展
- Control Widgets
- Home Screen Quick Actions
- Notification Actions
- 远程自动规划、云同步和无审批写入

冻结能力不得在 production bundle 中注册，也不得驱动新的核心抽象或扩大产品承诺。

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
