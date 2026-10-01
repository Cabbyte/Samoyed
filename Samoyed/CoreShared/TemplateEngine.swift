import Foundation

// `TemplateEngine` 负责“模板体系”相关的全部纯规则。
//
// 可以把它理解成模板子系统里的业务引擎：
// - 从最近几天的 DayPlan 推导候选模板
// - 决定某个日期最终应该选哪份 SavedTemplate
// - 把模板实例化成具体某天的 DayPlan
// - 在规则允许时重建/再生成未来计划
//
// 之所以单独拆出来，而不是塞进 Store 或 View：
// 1. 规则可以独立测试
// 2. UI 不需要知道模板选择细节
// 3. DayPlanEngine 和 TemplateEngine 各自只关心一类复杂度
public enum TemplateEngine {
    public static func previewDayPlan(
        from savedTemplate: SavedDayTemplate,
        on date: LocalDay = LocalDay(year: 2001, month: 1, day: 1)
    ) throws -> DayPlan {
        // 预览模板时，我们只需要“把模板实例化到一个占位日期”。
        // 这里的日期不重要，重要的是让时间解析和结构校验都能跑起来。
        try instantiateDayPlan(
            from: savedTemplate,
            for: date,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    public static func suggestedTemplates(
        referenceDay: LocalDay,
        from dayPlans: [DayPlan]
    ) throws -> [SuggestedDayTemplate] {
        // 当前产品规则规定：候选模板只看最近 3 天窗口。
        // 先按日期建表，顺便检查是否有重复的 DayPlan。
        var dayPlansByDate: [LocalDay: DayPlan] = [:]

        for dayPlan in dayPlans {
            if dayPlansByDate.updateValue(dayPlan, forKey: dayPlan.date) != nil {
                throw SamoyedCoreError.duplicateDayPlanForDate(dayPlan.date)
            }
        }

        let windowDates = [
            referenceDay.adding(days: -2),
            referenceDay.adding(days: -1),
            referenceDay
        ]

        // `compactMap` 在这里表示：
        // - 没有 DayPlan 的日期 -> 直接跳过
        // - 有 DayPlan 的日期 -> 转成 SuggestedTemplate
        return try windowDates.compactMap { date in
            guard let dayPlan = dayPlansByDate[date] else { return nil }
            return try suggestedTemplate(from: dayPlan)
        }
    }

    public static func saveSuggestedTemplate(
        _ suggestedTemplate: SuggestedDayTemplate,
        title: String,
        createdAt: Date = Date()
    ) -> SavedDayTemplate {
        // 候选模板保存成正式模板时必须 deep copy，
        // 否则后面编辑正式模板会反向影响候选模板摘要，造成引用污染。
        let copiedBlocks = deepCopy(blocks: suggestedTemplate.blocks)
        return SavedDayTemplate(
            title: title,
            sourceSuggestedTemplateID: suggestedTemplate.id,
            blocks: copiedBlocks,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public static func makeSimpleSavedTemplate(
        title: String,
        blocks: [BlockTemplate],
        createdAt: Date = Date()
    ) throws -> SavedDayTemplate {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw SamoyedCoreError.emptyTemplateTitle
        }
        guard !blocks.isEmpty else {
            throw SamoyedCoreError.emptyTemplateBlocks
        }

        for block in blocks {
            guard block.layerIndex == 0, block.parentTemplateBlockID == nil else {
                throw SamoyedCoreError.invalidRootBlock(block.id)
            }
            guard case .absolute = block.timing else {
                throw SamoyedCoreError.baseBlockMustUseAbsoluteTiming(block.id)
            }
        }

        let sortedBlocks = normalized(blocks: blocks).sorted { lhs, rhs in
            let lhsStart = absoluteStart(of: lhs)
            let rhsStart = absoluteStart(of: rhs)
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let template = SavedDayTemplate(
            title: trimmedTitle,
            blocks: sortedBlocks,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        _ = try previewDayPlan(from: template)
        return template
    }

    public static func activate(
        document: SamoyedDocument,
        template: SavedDayTemplate,
        assignedWeekdays: Set<Weekday>,
        today: LocalDay,
        activatedAt: Date = Date()
    ) throws -> SamoyedDocument {
        guard !assignedWeekdays.isEmpty else {
            throw SamoyedCoreError.emptyActivationWeekdays
        }
        _ = try previewDayPlan(from: template)

        var activated = document
        activated.savedTemplates.removeAll { $0.id == template.id }
        activated.savedTemplates.append(template)
        activated.weekdayRules.removeAll { rule in
            rule.savedTemplateID == template.id || assignedWeekdays.contains(rule.weekday)
        }
        activated.weekdayRules.append(contentsOf: assignedWeekdays
            .sorted { $0.rawValue < $1.rawValue }
            .map { WeekdayTemplateRule(weekday: $0, savedTemplateID: template.id) })
        activated.weekdayRules.sort { $0.weekday.rawValue < $1.weekday.rawValue }

        let outcome = try chooseTemplate(
            for: today,
            templateID: template.id,
            source: .pickedTemplate,
            existingDayPlans: activated.dayPlans,
            savedTemplates: activated.savedTemplates,
            selectedAt: activatedAt,
            forceReplace: true
        )

        guard case let .applied(selection, dayPlan) = outcome else {
            return activated
        }
        activated.daySelections.removeAll { $0.date == today }
        activated.daySelections.append(selection)
        activated.dayPlans.removeAll { $0.date == today }
        activated.dayPlans.append(dayPlan)
        activated.dayPlans.sort { $0.date < $1.date }
        return activated
    }

    public static func selectedSavedTemplate(
        for date: LocalDay,
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride],
        daySelections: [DayTemplateSelection] = []
    ) throws -> SavedDayTemplate? {
        let templateByID = Dictionary(uniqueKeysWithValues: savedTemplates.map { ($0.id, $0) })

        if let selection = latestDaySelection(for: date, in: daySelections) {
            guard let selectedTemplateID = selection.selectedTemplateID else {
                return nil
            }

            guard let template = templateByID[selectedTemplateID] else {
                throw SamoyedCoreError.missingSavedTemplate(selectedTemplateID)
            }

            return template
        }

        return try automaticSavedTemplate(
            for: date,
            templateByID: templateByID,
            weekdayRules: weekdayRules,
            overrides: overrides
        )
    }

    public static func requiresExplicitTemplateSelection(
        for date: LocalDay,
        today: LocalDay,
        existingDayPlans: [DayPlan],
        daySelections: [DayTemplateSelection]
    ) throws -> Bool {
        // v0.3 defaults run automatically. This compatibility query remains for
        // frozen system surfaces, but the product no longer has a daily chooser gate.
        _ = date
        _ = today
        _ = existingDayPlans
        _ = daySelections
        return false
    }

    public static func chooseTemplate(
        for date: LocalDay,
        templateID: UUID?,
        source: DayTemplateSelectionSource,
        existingDayPlans: [DayPlan],
        savedTemplates: [SavedDayTemplate],
        selectedAt: Date = Date(),
        forceReplace: Bool = false
    ) throws -> DayTemplateChoiceOutcome {
        let existingPlan = try uniqueDayPlan(for: date, in: existingDayPlans)

        if let existingPlan, !forceReplace, (existingPlan.hasUserEdits || existingPlan.containsCompletedTasks) {
            return .requiresForceReplace
        }

        let selection = DayTemplateSelection(
            date: date,
            selectedTemplateID: templateID,
            source: source,
            selectedAt: selectedAt
        )
        let dayPlanID = existingPlan?.id ?? UUID()

        if let templateID {
            guard let template = savedTemplates.first(where: { $0.id == templateID }) else {
                throw SamoyedCoreError.missingSavedTemplate(templateID)
            }

            return .applied(
                selection: selection,
                dayPlan: try instantiateDayPlan(
                    from: template,
                    for: date,
                    dayPlanID: dayPlanID,
                    generatedAt: selectedAt
                )
            )
        }

        return .applied(
            selection: selection,
            dayPlan: DayPlan(
                id: dayPlanID,
                date: date,
                sourceSavedTemplateID: nil,
                lastGeneratedAt: selectedAt,
                hasUserEdits: false,
                blocks: []
            )
        )
    }

    private static func automaticSavedTemplate(
        for date: LocalDay,
        templateByID: [UUID: SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride]
    ) throws -> SavedDayTemplate? {
        // 这里体现了自动模板选择优先级：
        // 具体日期 override > 星期规则 weekday rule > 没有模板(nil)
        var overrideByDate: [LocalDay: UUID] = [:]
        for override in overrides {
            if overrideByDate.updateValue(override.savedTemplateID, forKey: override.date) != nil {
                throw SamoyedCoreError.duplicateDateOverride(override.date)
            }
        }

        if let overrideTemplateID = overrideByDate[date] {
            guard let template = templateByID[overrideTemplateID] else {
                throw SamoyedCoreError.missingSavedTemplate(overrideTemplateID)
            }
            return template
        }

        var ruleByWeekday: [Weekday: UUID] = [:]
        for rule in weekdayRules {
            // weekday 调度规则是 1:1 映射：一个星期几只能指向一份模板。
            if ruleByWeekday.updateValue(rule.savedTemplateID, forKey: rule.weekday) != nil {
                throw SamoyedCoreError.duplicateWeekdayRule(rule.weekday)
            }
        }

        guard let ruleTemplateID = ruleByWeekday[date.weekday] else {
            return nil
        }

        guard let template = templateByID[ruleTemplateID] else {
            throw SamoyedCoreError.missingSavedTemplate(ruleTemplateID)
        }
        return template
    }

    public static func instantiateDayPlan(
        from savedTemplate: SavedDayTemplate,
        for date: LocalDay,
        dayPlanID: UUID = UUID(),
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        // 模板里的 block ID 只是“模板内部身份”；
        // 真正落到某天计划里时，必须生成新的 ID，避免模板和实例共享身份。
        var blockIDMap: [UUID: UUID] = [:]

        for block in savedTemplate.blocks {
            // 给每个模板 block 预先分配一个新 UUID，稍后父子关系也通过这张映射表重写。
            blockIDMap[block.id] = UUID()
        }

        let instantiatedBlocks = try savedTemplate.blocks.map { blockTemplate -> TimeBlock in
            guard let blockID = blockIDMap[blockTemplate.id] else {
                throw SamoyedCoreError.missingBlock(blockTemplate.id)
            }

            let parentBlockID: UUID?
            if let parentTemplateBlockID = blockTemplate.parentTemplateBlockID {
                // 父子引用也必须一起 remap，否则子节点还会指向模板里的旧父 ID。
                guard let mappedParentID = blockIDMap[parentTemplateBlockID] else {
                    throw SamoyedCoreError.missingTemplateParent(
                        blockID: blockTemplate.id,
                        parentID: parentTemplateBlockID
                    )
                }
                parentBlockID = mappedParentID
            } else {
                parentBlockID = nil
            }

            let tasks = blockTemplate.taskBlueprints
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { blueprint in
                    // 模板任务在实例化时一律变成“未完成”的真实任务。
                    var task = TaskItem(
                        title: blueprint.title,
                        order: blueprint.order,
                        isCompleted: false,
                        completedAt: nil
                    )
                    task.sourceTaskID = blueprint.id
                    return task
                }

            var block = TimeBlock(
                id: blockID,
                dayPlanID: dayPlanID,
                parentBlockID: parentBlockID,
                layerIndex: blockTemplate.layerIndex,
                title: blockTemplate.title,
                note: blockTemplate.note,
                reminders: blockTemplate.reminders,
                tasks: tasks,
                timing: blockTemplate.timing
            )
            block.sourceBlockID = blockTemplate.id
            return block
        }

        let plan = DayPlan(
            id: dayPlanID,
            date: date,
            sourceSavedTemplateID: savedTemplate.id,
            lastGeneratedAt: generatedAt,
            hasUserEdits: false,
            blocks: instantiatedBlocks
        )
        // 模板实例化完成后仍然要走 `DayPlanEngine.resolved`，
        // 因为 block 的 resolved 时间、结构合法性都还需要重新计算。
        return try DayPlanEngine.resolved(plan)
    }

    public static func ensureMaterializedDayPlan(
        for date: LocalDay,
        existingDayPlans: [DayPlan],
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride],
        daySelections: [DayTemplateSelection] = [],
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        // 已存在的 DayPlan 永远优先视为真实来源，不会被模板再次覆盖。
        if let existingPlan = try uniqueDayPlan(for: date, in: existingDayPlans) {
            return existingPlan
        }

        guard let selectedTemplate = try selectedSavedTemplate(
            for: date,
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: overrides,
            daySelections: daySelections
        ) else {
            // 没匹配到模板不是错误，而是一种合法状态：当天就是空计划。
            return DayPlan(
                date: date,
                sourceSavedTemplateID: nil,
                lastGeneratedAt: generatedAt,
                hasUserEdits: false,
                blocks: []
            )
        }

        return try instantiateDayPlan(
            from: selectedTemplate,
            for: date,
            generatedAt: generatedAt
        )
    }

    public static func regenerateFutureDayPlan(
        for date: LocalDay,
        today: LocalDay,
        existingDayPlans: [DayPlan],
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride],
        daySelections: [DayTemplateSelection] = [],
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        // regenerate 是“保守”的未来计划再生成：
        // 允许系统刷新未来计划，但尽量不碰用户已经明确动过的内容。
        guard date > today else {
            throw SamoyedCoreError.regenerationNotAllowedForNonFutureDate(date)
        }

        guard let existingPlan = try uniqueDayPlan(for: date, in: existingDayPlans) else {
            throw SamoyedCoreError.missingDayPlanForDate(date)
        }

        if existingPlan.hasUserEdits {
            throw SamoyedCoreError.regenerationBlockedByUserEdits(date)
        }

        if existingPlan.containsCompletedTasks {
            throw SamoyedCoreError.regenerationBlockedByCompletedTasks(date)
        }

        guard let selectedTemplate = try selectedSavedTemplate(
            for: date,
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: overrides,
            daySelections: daySelections
        ) else {
            return DayPlan(
                id: existingPlan.id,
                date: date,
                sourceSavedTemplateID: nil,
                lastGeneratedAt: generatedAt,
                hasUserEdits: false,
                blocks: []
            )
        }

        return try instantiateDayPlan(
            from: selectedTemplate,
            for: date,
            dayPlanID: existingPlan.id,
            generatedAt: generatedAt
        )
    }

    public static func rebuildDayPlan(
        for date: LocalDay,
        existingDayPlans: [DayPlan],
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride],
        daySelections: [DayTemplateSelection] = [],
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        let existingPlan = try uniqueDayPlan(for: date, in: existingDayPlans)
        let dayPlanID = existingPlan?.id ?? UUID()

        guard let selectedTemplate = try selectedSavedTemplate(
            for: date,
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: overrides,
            daySelections: daySelections
        ) else {
            return DayPlan(
                id: dayPlanID,
                date: date,
                sourceSavedTemplateID: nil,
                lastGeneratedAt: generatedAt,
                hasUserEdits: false,
                blocks: []
            )
        }

        return try instantiateDayPlan(
            from: selectedTemplate,
            for: date,
            dayPlanID: dayPlanID,
            generatedAt: generatedAt
        )
    }

    public static func updateSavedTemplate(
        _ templateID: UUID,
        title: String,
        blocks: [BlockTemplate],
        assignedWeekdays: Set<Weekday>,
        in document: SamoyedDocument,
        updatedAt: Date = Date()
    ) throws -> SamoyedDocument {
        // Updating a saved template is modeled as a pure transformation:
        // input document -> output document.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw SamoyedCoreError.emptyTemplateTitle
        }

        guard let templateIndex = document.savedTemplates.firstIndex(where: { $0.id == templateID }) else {
            throw SamoyedCoreError.missingSavedTemplate(templateID)
        }

        var updatedDocument = document
        var updatedTemplate = updatedDocument.savedTemplates[templateIndex]
        updatedTemplate.title = trimmedTitle
        updatedTemplate.blocks = normalized(blocks: blocks)
        updatedTemplate.updatedAt = updatedAt

        _ = try previewDayPlan(from: updatedTemplate)

        updatedDocument.savedTemplates[templateIndex] = updatedTemplate
        // Normalize weekday ownership by removing both the template's previous rules and
        // any conflicting rules for weekdays newly claimed by this template.
        updatedDocument.weekdayRules.removeAll {
            $0.savedTemplateID == templateID || assignedWeekdays.contains($0.weekday)
        }
        updatedDocument.weekdayRules.append(
            contentsOf: assignedWeekdays.sorted { $0.rawValue < $1.rawValue }.map {
                WeekdayTemplateRule(weekday: $0, savedTemplateID: templateID)
            }
        )
        updatedDocument.weekdayRules.sort { $0.weekday.rawValue < $1.weekday.rawValue }
        return updatedDocument
    }

    public static func deleteSavedTemplate(
        _ templateID: UUID,
        from document: SamoyedDocument
    ) -> SamoyedDocument {
        var updatedDocument = document
        updatedDocument.savedTemplates.removeAll { $0.id == templateID }
        updatedDocument.weekdayRules.removeAll { $0.savedTemplateID == templateID }
        updatedDocument.overrides.removeAll { $0.savedTemplateID == templateID }
        updatedDocument.dayPlans = updatedDocument.dayPlans.map { dayPlan in
            guard dayPlan.sourceSavedTemplateID == templateID else { return dayPlan }
            var updatedDayPlan = dayPlan
            updatedDayPlan.sourceSavedTemplateID = nil
            return updatedDayPlan
        }
        return updatedDocument
    }

    private static func suggestedTemplate(from dayPlan: DayPlan) throws -> SuggestedDayTemplate? {
        // Suggestions are learned from real user-visible blocks only.
        let resolvedPlan = try DayPlanEngine.resolved(dayPlan)
        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled && !$0.isBlankBaseBlock }

        guard !activeBlocks.isEmpty else {
            return nil
        }

        let blockTemplates = deepCopy(blocks: activeBlocks.map { block in
            BlockTemplate(
                id: block.id,
                parentTemplateBlockID: block.parentBlockID,
                layerIndex: block.layerIndex,
                title: block.title,
                note: block.note,
                reminders: block.reminders,
                taskBlueprints: block.tasks.map {
                    TaskBlueprint(id: $0.id, title: $0.title, order: $0.order)
                },
                timing: block.timing
            )
        })

        return SuggestedDayTemplate(
            sourceDate: resolvedPlan.date,
            sourceDayPlanID: resolvedPlan.id,
            blocks: blockTemplates
        )
    }

    private static func uniqueDayPlan(
        for date: LocalDay,
        in dayPlans: [DayPlan]
    ) throws -> DayPlan? {
        // Keeps the "at most one plan per date" invariant explicit.
        let matchingPlans = dayPlans.filter { $0.date == date }

        if matchingPlans.count > 1 {
            throw SamoyedCoreError.duplicateDayPlanForDate(date)
        }

        return matchingPlans.first
    }

    private static func latestDaySelection(
        for date: LocalDay,
        in daySelections: [DayTemplateSelection]
    ) -> DayTemplateSelection? {
        daySelections
            .filter { $0.date == date }
            .sorted { lhs, rhs in
                if lhs.selectedAt != rhs.selectedAt {
                    return lhs.selectedAt < rhs.selectedAt
                }
                let lhsID = lhs.selectedTemplateID?.uuidString ?? ""
                let rhsID = rhs.selectedTemplateID?.uuidString ?? ""
                return lhsID < rhsID
            }
            .last
    }

    private static func deepCopy(blocks: [BlockTemplate]) -> [BlockTemplate] {
        // Value copying alone would preserve logical IDs. We intentionally create a new
        // identity graph so saved templates and suggested templates stay independent.
        var blockIDMap: [UUID: UUID] = [:]
        for block in blocks {
            blockIDMap[block.id] = UUID()
        }

        return blocks.map { block in
            let copiedTaskBlueprints = block.taskBlueprints.map { blueprint in
                TaskBlueprint(title: blueprint.title, order: blueprint.order)
            }

            return BlockTemplate(
                id: blockIDMap[block.id] ?? UUID(),
                parentTemplateBlockID: block.parentTemplateBlockID.flatMap { blockIDMap[$0] },
                layerIndex: block.layerIndex,
                title: block.title,
                note: block.note,
                reminders: block.reminders,
                taskBlueprints: copiedTaskBlueprints,
                timing: block.timing
            )
        }
    }

    private static func normalized(blocks: [BlockTemplate]) -> [BlockTemplate] {
        // Persist contiguous task order values so later sorting reflects the current UI order.
        blocks.map { block in
            var updatedBlock = block
            updatedBlock.taskBlueprints = block.taskBlueprints.enumerated().map { index, blueprint in
                var updatedBlueprint = blueprint
                updatedBlueprint.order = index
                return updatedBlueprint
            }
            return updatedBlock
        }
    }

    private static func absoluteStart(of block: BlockTemplate) -> Int {
        switch block.timing {
        case let .absolute(startMinuteOfDay, _):
            return startMinuteOfDay
        case .relative:
            return .max
        }
    }
}
