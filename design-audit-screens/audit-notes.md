# Samoyed Design Audit Notes

审阅日期：2026-06-12

历史审阅记录：以下截图与问题对应当时版本，不作为当前待办清单。当前界面合同见 [Design.md](../Design.md)，后续修复见 [Today/Nest QA](../docs/qa/2026-10-02-today-nest-ui.md)。

范围：根据 `Design.md`、`PRD.md`、`SystemSurfaces.md`，结合 iPhone 17 Pro 模拟器实机截图，审阅当前主 App 与系统表面设计的不完善处。

## 截图证据

1. `01-now-open-time.jpg` - Now 空白时段首屏。
2. `02-today-timeline.jpg` - Today 时间轴默认视图。
3. `03-today-inspector.jpg` - Today 选中 block 后的底部 inspector。
4. `04-library-root.jpg` - Library 根页面。
5. `05-templates-today.jpg` - Templates 今日选择首屏。
6. `06-templates-saved.jpg` - Templates Saved 区域。
7. `07-templates-schedule.jpg` - Templates Schedule / Defaults 区域。

## 主要结论

当前 UI 的工程完成度不低，三大 tab、时间轴嵌套、模板选择、Widget/Live Activity 的基础都已经成形；问题主要不是“功能缺失”，而是设计叙事和视觉权重还没有完全贴合文档里的产品心智。

最核心的偏差是：

- `Now` 还在强调“当前块摘要”，而不是把未完成 checklist 作为绝对焦点。
- `Today` 的详情面板是自绘 docked panel，不是文档要求的原生 sheet 体验。
- `Templates / Library` 已经强化了“每日显式选择”，但状态文案和信息架构还会让用户困惑“今天到底在运行哪一种生活模板”。
- 模板卡片看起来完整，但多个模板之间的差异不够可读，仍偏统计数字和操作按钮。
- 系统表面有正确方向，但 Widget 任务排序存在让已完成任务抢先展示的风险。

## 分步健康度

1. Now 空白时段：中等偏弱。空态表达明确，但首屏先展示大块 `Open Time` hero，再展示 Tasks 空态，和“Tasks 是重心”的设计目标冲突。
2. Today 时间轴：较好。Base / overlay 嵌套关系基本符合文档，空白时段低权重显示也成立；但顶部工具栏形成了偏浮动控制组，仍需看是否过于抢占注意。
3. Today inspector：偏弱。功能清楚，但是自绘浮动卡片，有关闭按钮和阴影，偏离原生 bottom sheet / inspector 的方向。
4. Library 根页面：中等。系统感强，但更像 Workspace / Settings 中心，而不是模板资产库。
5. Templates 今日选择：中等偏弱。强化了“今天选择”，方向符合 PRD；但 `Running`、`No template today`、`Default Workday` 同屏并存，状态语义不够稳定。
6. Saved Templates：中等。已有 preview、stats、actions；但模板差异表达弱，按钮权重高，用户更容易先看见操作而不是理解模板。
7. Schedule / Defaults：中等偏弱。能编辑规则，但页面更像规则配置，弱化了“明天最终运行哪个模板”的产品重点。

## UX 风险

### 1. Now 的首屏重心被 hero 卡片拿走

文档要求 `Now` 页面重心落在 `Tasks`，不要显示大块 `Current Block` 卡片。当前实现中 `NowCurrentHeroView` 固定排在 `NowTasksSectionView` 前面，并且用 28px 圆角、强背景和描边做主视觉。

影响：

- 用户第一眼看到的是“我现在在哪个块”，不是“我现在该做什么”。
- 空白时段时，`Open Time` 信息重复出现两次，首屏显得轻但不够有行动焦点。
- 当有任务时，任务仍可能被当前块摘要压低。

建议：

- 将 hero 收敛为轻量状态行，或只在非空白、非任务清晰时显示。
- `Tasks` 应在有未完成任务时成为首屏第一块内容。
- BlankBaseBlock 的表达可以合并进 Tasks 空态，不必额外占一个大卡片。

### 2. Now 的 `Context` 命名和文档里的 `Notes` 不一致

文档定义 `Now` 自上而下是 `Notes` 与 `Tasks`，并强调 Notes 轻于 Tasks。当前代码里的 Notes section 标题是 `Context`，会让用户理解成系统上下文，而不是“固定地对自己说的话”。

影响：

- Note 的产品语义被稀释，容易变成状态解释区。
- `Context` 这个词也接近文档明确不想重复渲染的 activeChain 上下文。

建议：

- 将标题调整回 `Notes` 或更贴近日常提示的命名。
- 视觉上进一步轻量化 Notes，避免和任务卡片竞争。

### 3. Today inspector 偏离原生 sheet 方案

文档明确要求详情使用 iOS 原生 sheet，不提供单独关闭按钮，只通过下滑收起/隐藏。当前 `TodayDockedInspector` 通过 `safeAreaInset` 自绘底部卡片，包含关闭按钮、阴影、圆角背景和自定义 drag gesture。

影响：

- 和 iOS 系统 sheet 的交互预期不同。
- 关闭按钮让 inspector 更像 modal/card，而不是轻量 inspector。
- 自绘阴影和卡片感使 Today 的时间轴被遮挡感更强。

建议：

- 用系统 sheet detents 承接 block detail。
- 取消显式关闭按钮，保留系统 sheet 的自然下滑行为。
- 主区域只保留 `Edit` 和 `Add Overlay`，把 `Cancel Block` 继续放在编辑页 destructive 区域。

### 4. Templates 的文档版本和当前实现已经分叉

`Design.md` 仍写着 Templates 稳定包含 `Suggested / Saved / Schedule` 三部分；当前实现增加了顶部 `Today` 区域。这个变化符合 PRD 后续提出的“每日显式选择”方向，但设计文档没有被同步。

影响：

- 后续实现者不知道该服从旧的三段式，还是新的每日选择优先。
- 当前页面会同时承载“今天选择”“模板库”“默认规则”“候选保存”，首屏认知负担偏高。

建议：

- 更新 `Design.md`，明确新的 Templates IA：`Today` 是否是第一段，是否需要 tabs/segmented control。
- 将 `Today` 选择定义成产品主路径，而不是夹在模板库里的一个设置块。

### 5. 今日模板状态语义不稳定

截图 `05-templates-today.jpg` 中同时出现：

- `Running`
- `Current: No template today`
- `Default: Workday`
- `Today is intentionally empty until you pick another template.`
- `Recommended Default: Workday`
- `Use Default`

影响：

- 用户可能不知道今天到底是“已运行空模板”、还是“未选择”、还是“跟随默认 Workday”。
- `Running` 这个 badge 过于肯定，但 `No template today` 又削弱了它。

建议：

- 把状态拆成两个明确概念：`Today plan source` 和 `Available default`。
- 如果今天没有模板但已有可用默认，文案应明确：`Today is running without a template`，按钮为 `Switch to Workday`。
- 避免 `Current / Default / Recommended Default` 在同一块里重复表达。

### 6. 模板差异不够可读

Saved card 已有 preview chips 和 stats，但多个模板展示内容几乎一致：`Morning / Lunch / Afternoon / +3 more`、`4 base / 2 overlay / 11 tasks / 0 reminders`。这不满足 PRD 里“模板差异必须对用户可读”的要求。

影响：

- 用户难以理解 `Recent 1`、`Recent 2`、`Workday` 是怎样不同的一天。
- 操作按钮比模板内容更显眼，用户先被引导去 `Use Today`，而不是先判断是否适合。

建议：

- 增加更有辨识度的 day-shape summary，例如时间跨度、关键 overlay、任务密度最高的 block。
- 将 `Use Today` 的按钮权重降低到 trailing/secondary，至少不要压过模板主体。
- 对相似模板提供差异提示，例如 `Same structure as Workday` 或 `2 tasks changed`。

### 7. Schedule 仍偏规则配置，而不是明天结果

文档要求 Schedule 优先回答“明天最终用哪个模板”，规则编辑在后。当前 `defaultsSection` 先显示 Today card，再显示 Tomorrow card，然后是 Weekday Rules 和 overrides；视觉上像设置表单。

影响：

- 用户要读完多行 Default / Special Day / Current Result 才知道明天是什么。
- `Regenerate Tomorrow` 作为按钮进入视野较早，维护动作权重偏高。

建议：

- 把 Tomorrow final result 做成独立高优先级摘要。
- Weekday rules 放低，表现成设置列表。
- `Regenerate` 降级到更多菜单或低权重 maintenance action。

### 8. Library 根页不像模板资产库

PRD 定义 Library 优先回答“我有哪些生活模板、今天和明天要运行哪一个、如何导入外部编排结果”。当前 Library 首页首块是 `Workspace Status`，并把 `Tint` 放在同等状态 pill 里。

影响：

- 首屏更像开发者/设置中心，而不是用户的日结构资产库。
- `Tint` 抢占了和模板运行同级的状态位置。

建议：

- Library 首屏突出 Templates 和今日/明日运行状态。
- Appearance 可以保留，但不要放在首页 summary 的同等权重。
- `Workspace Status` 可改为更产品化的 `Running Plan` 或直接并入 Templates entry。

### 9. Widget 任务排序和产品焦点冲突

`SamoyedWidgetSupport.prioritizedTasks` 的注释明确说明当前排序会把已完成任务排在前面。Widget 空间有限，这会直接损害“未完成 checklist 是焦点”的目标。

影响：

- 中号 Widget 可能把已完成任务显示在未完成任务前。
- 系统表面本应是“轻轻告诉用户该做什么”，而不是展示完成历史。

建议：

- Widget 任务排序先未完成、再已完成。
- 如果空间不足，只展示未完成任务；完成任务可完全省略或仅做 summary。

### 10. 视觉系统局部偏“漂亮卡片化”

当前 UI 使用大量 24-28px 圆角卡片、描边、半透明背景和柔和阴影。单看很干净，但文档目标是更接近 Apple 官方 App，且强调内容优先、少装饰。

影响：

- Now / Templates / Library 都有较重卡片感，界面性格有时偏 dashboard。
- Widget 背景使用渐变和模糊圆形装饰，和系统表面“glanceable”目标有轻微张力。

建议：

- 内容页面卡片圆角和边界更接近系统 grouped list，而不是统一大圆角容器。
- 把装饰性渐变/模糊圆从 Widget 背景中弱化，更多依靠系统 widget container 和层级颜色。
- 保留 layer color 作为结构语义，但不要让色彩成为主要视觉戏剧。

## Accessibility 风险

- 图标按钮有 accessibility label 的迹象，但需要继续验证 VoiceOver 读序，尤其是 Today toolbar 的日期切换、定位、添加按钮。
- Today inspector 的自绘 drag/toggle 行为可能不如系统 sheet 对辅助技术稳定。
- Templates 中大量 badge/chip 需要确认动态字体下是否换行合理，尤其是 `Use Today / Use Tomorrow / Edit` 横排按钮。
- Widget 中任务行 1 行截断，长 checklist item 可能无法被充分理解；需要确认可访问标签是否包含完整任务名称和来源 block。

## 建议优先级

P0:

- 修正 Widget 任务排序，避免已完成任务抢占前 3 个展示位。
- 统一 Templates 今日状态文案，消除 `Running` + `No template today` 的矛盾。

P1:

- 重构 Now 首屏：让 Tasks 成为焦点，hero 降级或合并为空态。
- 将 Today detail 从自绘 docked inspector 收敛到原生 sheet 方案。
- 更新 `Design.md`，把 PRD 中“每日显式选择模板”的新 IA 写进去。

P2:

- 提升模板卡片的差异可读性，弱化操作按钮权重。
- Library 首屏从 workspace/status 中心转为模板资产库。
- Schedule 聚焦 Tomorrow final result，把规则编辑降级为设置。

P3:

- 调整整体卡片圆角、阴影、Widget 背景装饰，让视觉更贴近系统 App。
- 做动态字体、VoiceOver、深色模式和不同屏宽下的设计 QA。
