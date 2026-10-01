# Samoyed Design

本文档定义 Samoyed 的 iOS 产品结构、界面层级和术语。当前实现以 Frozen Figma `KMmryraXYpe4O2BTgadVjJ` 为产品合同：Samoyed 是一个 local-first routine runner；iPhone 负责运行、查看、反馈和审批 Suggestion，不负责结构编排。

如果本文档与 PRD 冲突，以 PRD 为准。

## 1. Design Goal

Samoyed 的界面目标是让用户稳定运行已经定义好的 routine，而不是在手机上临时规划或编辑一天。

UI 应帮助用户完成以下事情：

- 导入并理解可运行的 Routine Definition。
- 让 weekday default 自动运行，并允许为某一天选择另一个已批准 Routine 或 No Routine。
- 以只读时间线查看当天 Materialized Day。
- 在执行过程中完成 checklist item。
- 追加本地 Feedback，并审批或拒绝 Planner 产生的 Suggestion。

UI 不应承担：

- 可视化 routine builder。
- Today 页面里的 block 创建、删除、reparent、拖拽 resize、cancel 或 checklist/reminder 编辑。
- 从当天临时结构保存为 routine。
- task inbox 或 ad hoc todo capture。

## 2. Core Mental Model

用户心智应始终是：

1. 我先在配置文件或外部工具里定义 routine。
2. 我把 Routine Config File 导入 Samoyed。
3. App 根据 weekday default 自动选择今天的 routine。
4. 需要例外时，我从 Today 的当前 Routine 入口选择另一个已批准 Routine 或 No Routine。
5. App 把选择物化为当天运行快照；Feedback 与 checklist completion 都不会直接改动 Routine。
6. 结构改进必须先成为 Suggestion，经我批准后创建可追溯的新 Routine version。

## 3. Terminology

### 3.1 Routine Definition

`Routine Definition` 是 routine 结构的唯一权威来源。

它描述：

- routine 元信息，例如名称、说明、版本。
- block 结构。
- overlay / nested block 关系。
- 时间规则。
- note。
- checklist item。
- reminder rule。

它不保存：

- 某一天 checklist 的完成状态。
- 某一天的运行进度。
- 用户在当天临时做过什么。

### 3.2 Routine Config File

`Routine Config File` 是承载 `Routine Definition` 的具体文件。

产品概念不绑定 YAML。当前实现可以先支持 YAML，但设计语言应始终使用 `Routine Config File`，为 TOML、JSON 或其他可校验格式保留空间。

### 3.3 Routine Library

`Routine Library` 是本地保存的、已导入并通过校验的 Routine Definition 集合。

它负责：

- 展示可运行 routine。
- 预览 routine 的结构。
- 导入 Routine Config File。
- 导出 Routine Config File。
- 作为每日 routine 选择的来源。

它不是：

- 手机端 routine 编辑器。
- 模板编辑器。
- 当天计划编辑器。

### 3.4 Daily Routine Selection

`Daily Routine Selection` 是某个本地自然日选择的唯一 routine。

v1 规则：

- 一个自然日只能选择一个 routine。
- 不支持多个 routine 组合运行。
- 不通过 Today 页面拼装 routine。
- 切换今天的 routine 是明确的日级选择，不是 block 级编辑。

### 3.5 Materialized Day

`Materialized Day` 是 Daily Routine Selection 在某个日期上的运行快照。Today 与 Block Details 对结构完全只读；当天只允许 checklist completion 和显式 Routine 选择。

它包含：

- 当天 block 时间线。
- note。
- checklist item。
- reminder。
- 当前 active block / task source 等运行推导。

Materialized Day 可以缓存或持久化，但不能成为 routine 结构的权威来源。

### 3.6 Execution State

`Execution State` 是某一天的运行状态。

它包含：

- checklist item 是否完成。
- 完成时间。
- 当天当前选择或 UI selection。

它不改变：

- Routine Definition。
- Routine Config File。
- Routine Library 中的 routine 结构。

## 4. Data Hierarchy

```mermaid
flowchart TD
    A["Routine Config File<br/>(YAML/TOML/JSON etc.)"] --> B["Routine Definition<br/>(structure authority)"]
    B --> C["Routine Library<br/>(validated local routines)"]
    C --> D["Daily Routine Selection<br/>(one routine per local day)"]
    D --> E["Materialized Day<br/>(read-only projection)"]
    E --> F["Execution State<br/>(checklist completion only)"]
```

结构状态和执行状态必须分离：

- Structure state 来自 Routine Definition。
- Execution state 属于某一天。
- Checklist completion 不回写 Routine Definition。

## 5. Root Navigation

根界面使用 `TabView`，固定三个一级页面：

1. `Now`
2. `Today`
3. `Library`

推荐图标：

- `Now`: `bolt.circle`
- `Today`: `calendar`
- `Library`: `square.stack.3d.up`

## 6. Now

### Purpose

`Now` 回答：现在这个 routine 运行到哪里了？

### Shows

- 当前 active block。
- 当前 note。
- 当前 checklist item 或 checklist section。
- 距离当前 block 结束或下一段开始的时间提示。
- 当天尚未选择 routine 时的选择入口。

### Allows

- 勾选当前 checklist item。
- 打开 Today 中对应位置。
- 打开 Library 选择今天 routine。

### Does Not Allow

- 编辑 block。
- 编辑 note。
- 编辑 checklist 内容。
- 改时间。
- 新增临时任务。

## 7. Today

### Purpose

`Today` 回答：今天自动或显式选择的 Routine 被物化成了什么只读结构？

### Shows

- 查看优先的 timeline。
- block / overlay 层级。
- open time gap。
- selected block detail。
- note、checklist、reminder 的只读内容。
- checklist completion state。

### Allows

- 选择 block 查看详情。
- 展开或收起详情面板。
- 跳到当前 active block。
- 勾选 checklist item，前提是该 checklist item 是执行状态的一部分。
- 通过日期下的 Routine 入口选择已有 Routine 或 No Routine。
- 为当前 block 追加 Feedback；Feedback 不直接修改结构。

### Does Not Allow

- 创建 block。
- 修改 checklist、reminder 或 block 层级。
- 拖拽或 resize block。
- cancel block。
- add overlay。
- 保存今天为 routine。
- 将 open time gap 转换为 block。

## 8. Library

### Purpose

`Library` 回答：有哪些已确认的 routine 可以运行？今天要运行哪一个？

### Top-Level Areas

- `Routines`: Routine Library，展示已导入 routines，并允许选择今天的 routine。
- `Routine Config Files`: 导入、校验、导出配置文件。
- `Settings`: 与 routine 结构无关的显示偏好。

### Routines

Routines 页面应展示：

- 今日 routine 选择状态。
- Routine Library 中的 routine 列表。
- 每个 routine 的只读预览。
- block、overlay、checklist、reminder 的摘要。
- `Select for Today` 操作。

Routines 页面不展示：

- 编辑 routine 的 form。
- 从近期日期保存 routine 的按钮。
- weekday default / special day override 编辑器。
- tomorrow regenerate / rebuild 操作。

### Routine Config Files

Routine Config Files 页面应展示：

- Import Routine Config File。
- 通过 `samoyed://import-routine` 接收 Base64URL 内嵌 YAML 或 HTTPS YAML，并在 App 内解码/下载、校验和预览。
- 导入预览和校验结果。
- 导入后加入 Routine Library。
- Export Selected Routine。

导入行为必须是 library-level 操作：

- 不替换今天的 Materialized Day。
- 不修改当天 Execution State。
- 不把 checklist completion 混入 Routine Definition。
- deeplink 只作为传输来源；必须由用户确认后保存本地副本，不建立持续同步关系。

## 9. System Surfaces

Widgets、Live Activities、App Shortcuts 与 notifications 只服务运行和显示：

- 展示当前 routine 状态。
- 打开 Now、Today 或 Library。
- 完成当前 checklist item。

它们不得暴露：

- 创建 block。
- 编辑时间。
- 修改 routine。
- 切换结构，除非跳转回 App 进行明确的 Daily Routine Selection。

## 10. Visual Direction

整体视觉应接近 Apple 原生系统应用：

- 使用 `TabView`、`NavigationStack`、`List`、`ScrollView`、toolbar、sheet。
- 使用系统分组背景。
- 使用 SF Symbols。
- 使用动态字体。
- 保持信息密度清晰，不做营销式 landing page。

Today timeline 可以定制视觉，但必须保持结构只读的心智：

- selected state 可以高亮。
- open gap 可以显示，但不应使用加号暗示新增。
- block detail 只提供查看、完成 checklist、Feedback 与 Done，不出现结构编辑 action group。

## 11. Implementation Notes

当前代码中仍可能存在历史内部命名，例如 `TemplateEngine`、`SavedDayTemplate`、`TemplatesScreenModel`。这些是迁移期实现细节，不应出现在用户可见文案中，也不改变产品术语：

- 用户可见术语使用 Routine。
- 配置文件使用 Routine Config File。
- 结构权威使用 Routine Definition。
- 本地集合使用 Routine Library。

长期可以逐步把内部命名迁移到 Routine，但迁移不应重新引入 App-side editor。

## 12. Acceptance Checklist

- Today 没有 block create/delete/reparent/drag-resize/cancel/add overlay，也不编辑 checklist/reminder。
- Today 没有 save today as routine。
- Library 使用 Routines 和 Routine Config Files 术语。
- Routine Config File import 加入 library，不替换今天。
- weekday default 自动运行；日期级 Routine 选择只覆盖某个日期且不改变 Usual Week。
- Checklist completion 只改变 Execution State。
- Feedback append-only，不直接改变 Routine 或 DayPlan 结构。
- Planner 是可选外部 seam，只能创建 Suggestion；生产默认 disconnected。
- System surfaces 不提供结构编辑能力。
