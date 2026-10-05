# Samoyed 界面合同

更新：2026-10-05。产品范围以 [PRD.md](PRD.md) 为准，数据与时间语义见 [README.md](README.md)。本文记录已实现的运行终端界面，不包含旧的手机端编排器探索。

## 1. 设计目标与术语

用户应快速知道现在处于什么状态、有哪些固定提示和 checklist、今天整体如何运行。使用原生 NavigationStack、TabView、List、sheet、系统材质和 Dynamic Type，保持暗色视觉语言与可读性。

- Routine：可复用结构，内部兼容类型仍可使用 Template 命名。
- Materialized Day：某天已经保存的运行快照。
- Guidance：Routine/Block 固定提示语，界面只读。
- Timeline Note：按发生时间记录的独立内容，可关联具体 block instance。
- Execution State：当天 checklist 完成状态，不修改 Routine Definition。

页面读取 `SamoyedPresentation` 的 screen model，通过 `SamoyedStore` 提交意图。视图不自行解析时间、选择模板或维护另一套持久化真相。

## 2. 导航与首次使用

固定三个一级 Tab：Now、Today、Library。首次使用可安装 Starter Routine、导入配置、连接 Nest 或选择本地 No Routine；有默认规则后自动运行，不重复弹出每日选择步骤。

起步流程只显示实际可用的偏好和连接状态。当前不调度本地提醒，不请求没有对应运行能力的通知权限。生产 Planner 没有配置时显示 disconnected。

## 3. Now

展示当前 active chain、固定提示语、任务来源和下一状态。未完成 checklist 是主要操作，完成后可以撤销；任务来源可沿父层回退。

允许记录 Feedback、打开 Today 中的明确上下文，以及显式开始或结束 Live Activity。No Routine、Open Time、全部完成和读取错误必须区分，读取错误提供重试，不能用样例数据替代。

实色图标背景上的前景需要足够对比度。Now 和 Today 的数据必须来自同一天的有效快照。

## 4. Today

顶部显示所选日期、实际快照的 Routine 来源、相邻日期按钮及 Today 按钮。Today 回到当前日期和时刻，不直接打开 block inspector；查看历史日时不显示今天的当前时间线。

时间轴展示 base/overlay 层级、Open Time、任务完成状态以及按发生时间穿插的 Notes。普通时间轴无法可靠显示重合起点或辅助字号时使用 Agenda fallback，保留查看详情的入口。

- 选择 block 打开只读详情，允许 checklist completion、Feedback 和 Done。
- 当前 Routine 入口选择已有 Routine 或 No Routine，不修改 Usual Week。
- Note 预览可以截短，打开编辑器后必须保留完整文本、发生时间和关联。
- Notes 可以独立存在，包括没有 Routine 的日期。
- 禁止新增/删除 block、拖拽、resize、reparent、cancel、编辑 checklist/reminder 内容或保存今天为 Routine。

标题描述保存的计划来源；最新规则不同于保留的历史快照时，不用最新规则覆盖标题。

## 5. Library 与 Nest

Library 包含 Routines、Usual Week、Routine Files、Appearance、Suggestions、Planner 和 Nest 入口。Routine 行和详情可只读预览、选择用于今天；Usual Week 为星期选择已有 Routine 或 No Routine。

Library 的紧凑 Nest 摘要与账号页的展开摘要使用真实同步状态。最近一次成功不能遮盖当前错误、待上传操作或冲突。账号页分开组织同步/时区/冲突操作、账号元数据和安全入口，保留本地模式、首次导入与重试路径。

Routine Files 支持配置校验、预览、确认导入和导出。导入只写 Routine Library，不直接替换今天或携带当天完成状态；在 Nest 分区中使用正常同步机制。配置文件来源不等于订阅。

固定提示语在 Routine 预览中只读；Timeline Note 编辑、删除和冲突处理是另一条内容流程。Feedback 保持 append-only，Suggestions 保持明确审批。

## 6. 系统表面与视觉参考

[SystemSurfaces.md](SystemSurfaces.md) 是系统入口的唯一界面合同。Widget 和 Live Activity 只展示或完成明确的 checklist，不创建/编辑结构；普通刷新不自动开始 Live Activity。

视觉参考：Figma `KMmryraXYpe4O2BTgadVjJ`；Library `519:1365`，Nest `519:1366`。已导入的向量资源保留原几何形状，原生导航、列表、工具栏和 Tab 继续使用系统控件。

2026-06 的 `design-audit-screens` 是历史审阅证据；当前 UI 修复记录见 [Today/Nest QA](docs/qa/2026-10-02-today-nest-ui.md)。

## 7. 验收重点

- 自动运行、日期返回、Routine 来源与实际快照一致。
- Today 的结构只读，执行与 Timeline Notes 操作可用。
- 长标题、长 Note、重合起点及辅助字号仍可读取和操作。
- No Routine、空闲、全部完成、离线、同步冲突与错误不混为同一状态。
- 本地与 Nest 模式均可打开日常主路径；显示的连接和同步状态真实。
- Widget、Live Activity 与 App 使用同一任务标识和完成语义。
- 截图、自动化测试、用户初验和专项设备验收按各自覆盖范围记录。
