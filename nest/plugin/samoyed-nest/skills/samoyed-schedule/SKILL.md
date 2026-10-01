---
name: samoyed-schedule
description: 用户希望编排或修改 Samoyed Routine、星期规则、指定日期的已有时间块，或新增、补记、查询时间轴 Note 时使用。通过已授权的 Nest MCP 读写，手机会自动同步。
---

# Samoyed Nest 日程与 Note

先调用 `nest_connection_status` 取得当前账户和日程时区。身份来自连接的授权，所有工具都只访问此账户。不要请求或传递 user ID、token、邮箱或密码来切换账户。

## Routine 编排

1. 使用用户的语言，逐一询问会影响结构的缺失信息。区分可重复 Routine、Checklist 步骤和带时间点的 Note。首版不创建独立的一次性安排。
2. 调用 `list_routines` 或 `read_entity`，取得对象当前修订号和稳定 ID。修改时保留现有 block 与 task ID；新对象才生成 UUID。固定提示文字使用 `guidance`；旧配置的 `note` 与其兼容。
3. 未指定生效日期的 Routine 和星期规则修改默认从账户时区的明天生效，在结果中说明日期。只有用户明确指定今天时才写今天的 `effectiveFrom`。特定日期选 Routine 使用 `dateException`，清空当日选择用 `savedTemplateID: null`。
4. 每个块需要开始时间。基础块使用 absolute，真正位于父块内部的状态才使用 relative，并提供正确层级与父 ID。同级块不能重叠；子块不能超出父范围。Checklist 完成状态只属于执行实例。
5. 用户已要求保存或修改时直接调用写工具。成功的服务器回执意味着已保存，手机无需再次确认；手机尚未同步时不要声称已显示。
6. 对某天已有块的修正先 `resolve_day`，用实例 ID 与计划修订号调用 `save_change` 的 `dayCorrection`。该操作不创建新的独立安排。

## Timeline Note

- `save_note` 支持新建、修改和补记纯文本 Note；用 `delete_entity` 传播删除标记。
- `occurredAt` 是事情发生的时间，决定时间轴位置。晚上补记下午的事情仍填写下午时间。保存 IANA 时区，区分有偏移量的真实时刻与本地钟点；有歧义时询问用户。
- Note 可独立存在。只有用户明确关联某天某块时，读取该天实例并填 `blockInstanceID`，不能填模板 block ID。删除 Routine 不删除 Note。
- Note 不占计划时长，不参与重叠计算，也不会自动完成 Checklist。需要改变任务状态时使用 `execution` 的明确 `isCompleted`，永远不要重试 toggle。
- `read_timeline` 按时间范围读取并继续分页，缺少记录不代表用户未执行，也可能手机离线尚未同步。读取 Note 只用于用户当前授权任务，不自动发送给其他聊天或外部服务。

## 重试与冲突

每项写入生成唯一 `operationID`。网络超时或响应丢失时使用完全相同的操作 ID、payload 与 `expectedRevision` 重试，不能悄悄产生第二条记录。已保存修改的新版本使用新操作 ID。

遇到 `revision_conflict`、`stale_plan` 或删除标记时先重新读取，向用户说明实质冲突。不要猜测新修订号并强行覆盖。用户决定合并后，以最新基准和新操作 ID 提交。已删除 ID 不复活；需要恢复内容时创建新 Note ID。

账户时区未初始化或需要切换时，先得到用户对具体时区的确认，再调用 `set_account_time_zone`。历史记录保留原时区。夏令时缺失钟点向后平移，重复钟点采用第一次出现。

`legacyPlan` 仅用于 iOS 首次数据迁移，不用于编排新计划。不要把本插件成功安装、工具已连接或 HTTP 成功，描述成真机同步已验收。
