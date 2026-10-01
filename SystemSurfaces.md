# Samoyed System Surfaces

- 版本：v1.0
- 日期：2026-08-14
- 状态：实现契约

系统表面只放大 Samoyed 已有的 `Now` 价值：低成本查看当前状态，以及完成一条明确的未完成 checklist。它们不承担 Routine、Template、Feedback 或 Suggestion 的创建和编辑。

## 1. 生产表面

| 表面 | 生产状态 | 允许的动作 |
| --- | --- | --- |
| Home Screen Widget | `systemSmall`、`systemMedium` | 打开当前内容；完成展示出的未完成 checklist |
| Accessory Widget | `accessoryInline`、`accessoryRectangular`、`accessoryCircular` | 打开当前内容 |
| Live Activity | Lock Screen | 打开当前内容；完成最多两条未完成 checklist |
| Dynamic Island | compact、minimal、expanded | 打开当前内容；expanded 可完成最多两条未完成 checklist |
| App Shortcuts | 六个固定 intent | Open Now、Open Today、Open Current Block、Complete Current Task、Start Live Activity、End Live Activity |
| Notification Actions | 共享 route/action 层 | 只使用明确的导航或完成动作 |

Control Widget 类型可以保留为兼容代码，但不注册到生产 `WidgetBundle`。

## 2. Widget 状态机

Widget 快照必须显式标记以下一种状态，UI 不得根据 `remainingTaskCount == 0` 自行猜测：

| 状态 | 进入条件 | 表现与跳转 |
| --- | --- | --- |
| `active` | 存在未完成 checklist | 展示当前层级与未完成数；medium 最多提供三条完成动作 |
| `caughtUp` | 当前存在有效非空 block，且未完成数为零 | 中性完成态；不是错误态 |
| `needsSetup` | 尚无可激活文档或今天没有 Routine | 明确提示选择 Routine；跳转 Library |
| `unavailable` | 有数据但当前没有有效非空 block，或读取失败 | 明确提示打开 Samoyed；不得渲染为 caught-up |

所有 Widget action 都是 completion-only：快照不包含已完成任务，交互 intent 只接受 `false → true`，重复执行保持可预测。系统支持五个 WidgetKit family；加上 Live Activity 构成六类已交付系统表面。

## 3. Accessory、Live Activity 与 Dynamic Island

Accessory Widget 复用同一四态快照，并通过状态一致的图标表达语义：

- active：`checklist`
- caught-up：`checkmark`
- needs-setup：`slider.horizontal.3`
- unavailable：`exclamationmark.triangle`

Live Activity 只有已开始的 Activity 才会被同步。App 或 extension 的普通文档写入只更新现有 Activity，不得隐式创建新的 Activity。其展示态为：

- active：当前 block 自己提供 note/checklist，使用 `checklist`。
- fallback：从父层 block 提供 note/checklist，使用 `arrow.turn.down.right` 并标明来源。
- caught-up：未完成数为零，使用 `checkmark`。

Lock Screen 与 Dynamic Island 使用同一 ContentState、同一 deep link 和相同的最多两条未完成动作。

## 4. 路由和写入边界

- 系统入口统一通过 `SamoyedSystemRoute` 生成 URL。
- 目标 task/block 过期或不存在时安全失败，不猜测替代目标。
- Widget、Live Activity、App Intent 与 App 共享同一 repository 和原子写入路径。
- App 侧文档变更刷新 Widget，并同步已存在的 Live Activity。
- production intent 不提供 Feedback、Suggestion、Routine 或 Template authoring。

## 5. App Intents 冻结清单

保持且只保持六个可发现 App Shortcut：

1. Open Now
2. Open Today
3. Open Current Block
4. Complete Current Task
5. Start Live Activity
6. End Live Activity

Widget/Live Activity 使用的内部 intent 必须 `isDiscoverable = false` 或仅作为 `LiveActivityIntent` 交互桥接，不计入上述公开清单。

## 6. 回归测试

每次改动至少验证：

- `active` 快照优先当前/task-source section，过滤已完成 task，并正确统计全部未完成数。
- 无持久化文档、空激活文档、no-routine 分别进入 `needsSetup`，不进入 caught-up。
- 有效 block 且无未完成 task 进入 `caughtUp`；没有有效 block 进入 `unavailable`。
- 时间线在当前 block 结束时间或 15 分钟兜底时间中的较早者刷新。
- completion-only 写入幂等；过期 ID 安全失败；Widget 写入后刷新 timeline 和已存在 Live Activity。
- 五个 Widget family 均能渲染 active/caught-up/needs-setup/unavailable。
- Live Activity 与 Dynamic Island 的 active/fallback/caught-up 图标、来源标签、两条动作上限一致。
- 六个 App Shortcuts 可发现且 deep link 参数正确；不存在 Feedback/Suggestion authoring intent。
- 生产 Widget bundle 不注册 Controls。

## 7. 原则

系统表面的信息密度由尺寸决定，但状态语义、写入规则和跳转目标必须一致。任何新表面或 authoring 能力都需要单独产品决策，不因底层类型已存在而自动进入生产。
