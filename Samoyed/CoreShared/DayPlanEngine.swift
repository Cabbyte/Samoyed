import Foundation
import CryptoKit

// `DayPlanEngine` 是项目里最核心、也最“算法化”的业务规则引擎。
// 如果用 C++ 的视角理解，它很像一个纯函数式的“时间块树规则解释器”：
// - 输入：一个 `DayPlan`
// - 输出：校验后的、带解析结果的 `DayPlan`，或一个明确的业务错误
//
// 这个文件主要负责：
// - 验证结构是否合法：父子关系、层级、循环引用、时间范围
// - 把相对时间块解析成绝对分钟区间
// - 生成运行时空白块，让 UI 能把一天渲染成连续时间线
// - 计算某一时刻的 active chain
// - 提供安全编辑能力：取消 block、调整起止时间
//
// 一个很重要的阅读原则：
// 这里尽量保持“纯业务规则”，不涉及 SwiftUI、Widget、通知等系统表面。
public enum DayPlanEngine {
    // MARK: - Public Entry Points

    public static func validate(_ plan: DayPlan) throws {
        // 这里没有单独写一套“只校验不解析”的逻辑，
        // 而是直接复用 `resolved(_:)`。
        // 原因很直接：只要一个 plan 能被完整解析，就说明它满足结构和时间规则。
        _ = try resolved(plan)
    }

    public static func resolved(_ plan: DayPlan) throws -> DayPlan {
        // 第一步先剥掉运行时空白块。
        // 这些 block 只是 UI 为了补齐时间线临时生成的，不是用户真正保存的数据。
        let persistedPlan = strippedRuntimeBlocks(from: plan)
        // 第二步解析出每个 block 的绝对时间范围。
        let resolvedRanges = try resolveRanges(in: persistedPlan)

        var resolvedPlan = persistedPlan
        resolvedPlan.blocks = persistedPlan.blocks.map { block in
            var updatedBlock = block
            // 解析出的 start/end 会直接回写到 block 上，方便后续展示层和编辑逻辑使用。
            // 注意：这仍然是“计算结果”，不是用户手工输入的原始字段。
            if let range = resolvedRanges[block.id] {
                updatedBlock.resolvedStartMinuteOfDay = range.start
                updatedBlock.resolvedEndMinuteOfDay = range.end
            } else {
                updatedBlock.resolvedStartMinuteOfDay = nil
                updatedBlock.resolvedEndMinuteOfDay = nil
            }
            return updatedBlock
        }

        return resolvedPlan
    }

    public static func runtimeResolved(_ plan: DayPlan) throws -> DayPlan {
        // `runtimeResolved` 比 `resolved` 更进一步：
        // 它会把用户没定义的时间空档补成“空白基础块”。
        // 这样时间线 UI 和 active selection 逻辑就能把 0:00~24:00 看成连续覆盖。
        let resolvedPlan = try resolved(plan)
        var runtimePlan = resolvedPlan
        runtimePlan.blocks.append(contentsOf: makeBlankBaseBlocks(in: resolvedPlan))
        return runtimePlan
    }

    public static func cancelBlock(_ blockID: UUID, in plan: DayPlan) throws -> DayPlan {
        // “取消 block”不是单纯把 `isCancelled` 设成 true。
        // 因为这个 block 可能有子块，所以还要做一连串结构修复：
        // - 目标块自己标记为 cancelled
        // - 直接子块提升一层，并改写成绝对时间
        // - 更深层后代统一下移 layer
        // - 最终还要验证这些变化不会制造重叠或改变无关 block 的解析区间
        let resolvedPlan = try resolved(plan)
        guard let target = resolvedPlan.blocks.first(where: { $0.id == blockID }) else {
            throw SamoyedCoreError.missingBlock(blockID)
        }

        if target.isCancelled {
            return resolvedPlan
        }

        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled }
        let activeBlocksByID = Dictionary(uniqueKeysWithValues: activeBlocks.map { ($0.id, $0) })
        let childrenByParent = buildChildrenMap(from: activeBlocks)
        let directChildren = Set(childrenByParent[blockID] ?? [])
        let descendantIDs = collectDescendants(startingAt: blockID, childrenByParent: childrenByParent)
        // 记录取消前的解析区间，后面用来做回归式验证。
        let originalRanges = try resolvedRangeMap(from: activeBlocks)

        var updatedPlan = resolvedPlan

        for index in updatedPlan.blocks.indices {
            let currentID = updatedPlan.blocks[index].id

            if currentID == blockID {
                updatedPlan.blocks[index].isCancelled = true
                updatedPlan.blocks[index].resolvedStartMinuteOfDay = nil
                updatedPlan.blocks[index].resolvedEndMinuteOfDay = nil
                continue
            }

            if directChildren.contains(currentID) {
                guard let resolvedChild = activeBlocksByID[currentID] else {
                    throw SamoyedCoreError.missingBlock(currentID)
                }

                guard
                    let resolvedStart = resolvedChild.resolvedStartMinuteOfDay,
                    let resolvedEnd = resolvedChild.resolvedEndMinuteOfDay
                else {
                    throw SamoyedCoreError.invalidResolvedRange(blockID: currentID, start: -1, end: -1)
                }

                // 直接子块原来是“相对目标块”的，现在目标块取消了，
                // 所以要把它改造成对上一层父块直接成立的绝对块。
                updatedPlan.blocks[index].parentBlockID = target.parentBlockID
                updatedPlan.blocks[index].layerIndex -= 1
                updatedPlan.blocks[index].timing = .absolute(
                    startMinuteOfDay: resolvedStart,
                    requestedEndMinuteOfDay: resolvedEnd
                )
                updatedPlan.blocks[index].resolvedStartMinuteOfDay = nil
                updatedPlan.blocks[index].resolvedEndMinuteOfDay = nil
                continue
            }

            if descendantIDs.contains(currentID) {
                // 更深层后代不改 timing，只修正它们的层级。
                updatedPlan.blocks[index].layerIndex -= 1
                updatedPlan.blocks[index].resolvedStartMinuteOfDay = nil
                updatedPlan.blocks[index].resolvedEndMinuteOfDay = nil
            }
        }

        // 取消后先做一次风险检查，再重新解析，最后验证不相关 block 的区间没有漂移。
        try validateCancelOverlapRisk(in: updatedPlan, originalRanges: originalRanges)

        let reparsedPlan = try resolved(updatedPlan)
        try validatePreservedRanges(after: reparsedPlan, against: originalRanges, excluding: [blockID])
        return reparsedPlan
    }

    public static func resizeBounds(for blockID: UUID, in plan: DayPlan) throws -> BlockResizeBounds {
        // 这个函数给 UI 提供“合法拖拽边界”。
        // 设计思想是：把复杂约束都放在业务层算好，界面层只消费结果。
        // 这样手势代码不会散落一堆 if/else，也更容易测试。
        let resolvedPlan = try resolved(plan)
        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled }

        guard let target = activeBlocks.first(where: { $0.id == blockID }) else {
            throw SamoyedCoreError.missingBlock(blockID)
        }

        guard
            let resolvedStart = target.resolvedStartMinuteOfDay,
            let resolvedEnd = target.resolvedEndMinuteOfDay
        else {
            throw SamoyedCoreError.invalidResolvedRange(blockID: blockID, start: -1, end: -1)
        }

        let nextSiblingStart = activeBlocks
            .filter { $0.parentBlockID == target.parentBlockID && $0.id != blockID }
            .compactMap { sibling -> Int? in
                guard let siblingStart = sibling.resolvedStartMinuteOfDay else {
                    return nil
                }

                // 只关心当前 block 右侧最近的兄弟块。
                return siblingStart > resolvedStart ? siblingStart : nil
            }
            .min()

        let parentEnd: Int
        if let parentBlockID = target.parentBlockID {
            guard
                let parent = activeBlocks.first(where: { $0.id == parentBlockID }),
                let resolvedParentEnd = parent.resolvedEndMinuteOfDay
            else {
                throw SamoyedCoreError.missingParent(blockID: blockID, parentID: parentBlockID)
            }

            parentEnd = resolvedParentEnd
        } else {
            parentEnd = 24 * 60
        }

        let childrenByParent = buildChildrenMap(from: activeBlocks)
        let descendantIDs = collectDescendants(startingAt: blockID, childrenByParent: childrenByParent)
        // 一个 block 的结束时间不能早于任何后代块的结束时间，否则树结构会被截断。
        let deepestDescendantEnd = activeBlocks
            .filter { descendantIDs.contains($0.id) }
            .compactMap(\.resolvedEndMinuteOfDay)
            .max() ?? (resolvedStart + 5)

        let previousSiblingEnd = activeBlocks
            .filter { $0.parentBlockID == target.parentBlockID && $0.id != blockID }
            .compactMap { sibling -> Int? in
                guard
                    let siblingStart = sibling.resolvedStartMinuteOfDay,
                    let siblingEnd = sibling.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                return siblingStart < resolvedStart ? siblingEnd : nil
            }
            .max()

        let rawMinimumEnd = max(resolvedStart + 5, deepestDescendantEnd)
        let rawMaximumEnd = min(parentEnd, nextSiblingStart ?? parentEnd)
        // 业务里统一按 5 分钟粒度对齐，减少拖拽时的碎片值。
        let minimumEnd = rawMinimumEnd.roundedUp(toStep: 5)
        let maximumEnd = rawMaximumEnd.roundedDown(toStep: 5)

        let resolvedParentStart = parentStart(for: target, in: activeBlocks)
        let rawMinimumStart = max(previousSiblingEnd ?? resolvedParentStart, resolvedParentStart)
        let rawMaximumStart = resolvedEnd - 5
        let minimumStart = rawMinimumStart.roundedUp(toStep: 5)
        let maximumStart = rawMaximumStart.roundedDown(toStep: 5)

        guard minimumEnd <= maximumEnd else {
            throw SamoyedCoreError.invalidResolvedRange(
                blockID: blockID,
                start: resolvedStart,
                end: rawMaximumEnd
            )
        }

        guard minimumStart <= maximumStart else {
            throw SamoyedCoreError.invalidResolvedRange(
                blockID: blockID,
                start: rawMinimumStart,
                end: resolvedEnd
            )
        }

        let alignedCurrentStart = resolvedStart.aligned(
            toStep: 5,
            within: minimumStart ... maximumStart
        ) ?? minimumStart

        let validStartCandidates = Array(stride(from: minimumStart, through: maximumStart, by: 5))
            .filter { candidate in
                // 这里很关键：
                // 有些 start 虽然数值落在区间里，但会破坏子孙 overlay 的解析合法性，
                // 所以还要用引擎再模拟验证一遍。
                (try? candidateStartPreservesResolvedEnd(
                    candidate,
                    for: target,
                    in: resolvedPlan,
                    activeBlocks: activeBlocks
                )) == true
            }

        let effectiveMinimumStart = validStartCandidates.min() ?? alignedCurrentStart
        let effectiveMaximumStart = validStartCandidates.max() ?? alignedCurrentStart

        return BlockResizeBounds(
            blockID: blockID,
            startMinuteOfDay: resolvedStart,
            endMinuteOfDay: resolvedEnd.aligned(toStep: 5, within: minimumEnd ... maximumEnd) ?? minimumEnd,
            minimumStartMinuteOfDay: effectiveMinimumStart,
            maximumStartMinuteOfDay: effectiveMaximumStart,
            minimumEndMinuteOfDay: minimumEnd,
            maximumEndMinuteOfDay: maximumEnd
        )
    }

    public static func resizeBlockStart(
        _ blockID: UUID,
        in plan: DayPlan,
        proposedStartMinuteOfDay: Int
    ) throws -> DayPlan {
        // 编辑操作返回一个全新的 `DayPlan` 值，而不是原地修改共享对象。
        // 这和 C++ 里偏函数式/不可变数据的思路类似：
        // 规则更容易推理，也更适合做回归测试。
        let bounds = try resizeBounds(for: blockID, in: plan)
        let alignedStart = proposedStartMinuteOfDay.aligned(
            toStep: 5,
            within: bounds.minimumStartMinuteOfDay ... bounds.maximumStartMinuteOfDay
        ) ?? bounds.startMinuteOfDay
        var updatedPlan = try resolved(plan)

        guard let blockIndex = updatedPlan.blocks.firstIndex(where: { $0.id == blockID }) else {
            throw SamoyedCoreError.missingBlock(blockID)
        }

        let currentBlock = updatedPlan.blocks[blockIndex]
        guard let resolvedEnd = currentBlock.resolvedEndMinuteOfDay else {
            throw SamoyedCoreError.invalidResolvedRange(blockID: blockID, start: -1, end: -1)
        }

        updatedPlan.blocks[blockIndex].timing = try timingByMovingStart(
            of: currentBlock,
            to: alignedStart,
            preservingResolvedEndMinuteOfDay: resolvedEnd,
            activeBlocks: updatedPlan.blocks.filter { !$0.isCancelled }
        )

        updatedPlan.blocks[blockIndex].resolvedStartMinuteOfDay = nil
        updatedPlan.blocks[blockIndex].resolvedEndMinuteOfDay = nil

        return try resolved(updatedPlan)
    }

    public static func resizeBlockEnd(
        _ blockID: UUID,
        in plan: DayPlan,
        proposedEndMinuteOfDay: Int
    ) throws -> DayPlan {
        // 调整结束时间和调整开始时间的区别在于：
        // - 绝对块：直接改 requested end
        // - 相对块：要改的是相对时长 requested duration
        let bounds = try resizeBounds(for: blockID, in: plan)
        let alignedEnd = proposedEndMinuteOfDay.aligned(
            toStep: 5,
            within: bounds.minimumEndMinuteOfDay ... bounds.maximumEndMinuteOfDay
        ) ?? bounds.endMinuteOfDay
        var updatedPlan = try resolved(plan)

        guard let blockIndex = updatedPlan.blocks.firstIndex(where: { $0.id == blockID }) else {
            throw SamoyedCoreError.missingBlock(blockID)
        }

        switch updatedPlan.blocks[blockIndex].timing {
        case let .absolute(startMinuteOfDay, _):
            updatedPlan.blocks[blockIndex].timing = .absolute(
                startMinuteOfDay: startMinuteOfDay,
                requestedEndMinuteOfDay: alignedEnd
            )

        case let .relative(startOffsetMinutes, _):
            updatedPlan.blocks[blockIndex].timing = .relative(
                startOffsetMinutes: startOffsetMinutes,
                requestedDurationMinutes: max(alignedEnd - bounds.startMinuteOfDay, 5)
            )
        }

        updatedPlan.blocks[blockIndex].resolvedStartMinuteOfDay = nil
        updatedPlan.blocks[blockIndex].resolvedEndMinuteOfDay = nil

        return try resolved(updatedPlan)
    }

    public static func activeSelection(in plan: DayPlan, at minuteOfDay: Int) throws -> ActiveSelection {
        // 先做 runtime resolve，这样即使当前时刻落在“空白时间”里，也能选中一个空白 base block。
        let runtimePlan = try runtimeResolved(plan)
        let activeBlocks = runtimePlan.blocks
            .filter { !$0.isCancelled }
            .filter { block in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return false
                }

                return start <= minuteOfDay && minuteOfDay < end
            }
            .sorted { lhs, rhs in
                // 从最外层排到最内层，这样最终结果天然就是一条 active chain。
                if lhs.layerIndex != rhs.layerIndex {
                    return lhs.layerIndex < rhs.layerIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        if activeBlocks.isEmpty {
            return ActiveSelection(chain: [], taskSourceBlock: nil)
        }

        guard activeBlocks.first?.layerIndex == 0 else {
            throw SamoyedCoreError.activeBlocksDoNotFormUniqueChain(atMinuteOfDay: minuteOfDay)
        }

        // 活跃块必须形成一条严格的父子链，否则说明数据结构已经不自洽。
        for index in activeBlocks.indices.dropFirst() {
            let child = activeBlocks[index]
            let parent = activeBlocks[index - 1]

            if child.parentBlockID != parent.id || child.layerIndex != parent.layerIndex + 1 {
                throw SamoyedCoreError.activeBlocksDoNotFormUniqueChain(atMinuteOfDay: minuteOfDay)
            }
        }

        let taskSource = activeBlocks.reversed().first { $0.hasIncompleteTasks }
        // 任务来源取最内层、仍有未完成任务的块；这是“上层 overlay 优先”的体现。
        return ActiveSelection(chain: activeBlocks, taskSourceBlock: taskSource)
    }

    public static func upcomingActiveBlock(
        in plan: DayPlan,
        after minuteOfDay: Int
    ) throws -> UpcomingActiveBlock? {
        let resolvedPlan = try resolved(plan)
        let current = try activeSelection(in: resolvedPlan, at: minuteOfDay).activeBlock
        let currentUserBlockID = current?.isBlankBaseBlock == false ? current?.id : nil
        let boundaries = Set(
            resolvedPlan.blocks
                .filter { !$0.isCancelled && !$0.isBlankBaseBlock }
                .flatMap { block in
                    [block.resolvedStartMinuteOfDay, block.resolvedEndMinuteOfDay].compactMap { $0 }
                }
                .filter { minuteOfDay < $0 && $0 < 24 * 60 }
        ).sorted()

        for boundary in boundaries {
            guard let candidate = try activeSelection(in: resolvedPlan, at: boundary).activeBlock else {
                continue
            }
            guard !candidate.isBlankBaseBlock, candidate.id != currentUserBlockID else {
                continue
            }
            return UpcomingActiveBlock(block: candidate, transitionMinuteOfDay: boundary)
        }
        return nil
    }

    // MARK: - Resolution

    private static func strippedRuntimeBlocks(from plan: DayPlan) -> DayPlan {
        // 运行时空白块只是展示工件，不应该再次参与解析或被持久化。
        var sanitized = plan
        sanitized.blocks = plan.blocks.filter { !$0.isBlankBaseBlock }
        return sanitized
    }

    private static func resolveRanges(in plan: DayPlan) throws -> [UUID: (start: Int, end: Int)] {
        var allBlocksByID: [UUID: TimeBlock] = [:]

        for block in plan.blocks {
            // 后续很多算法都要通过 ID 做字典查找。
            // 一旦 ID 重复，树结构就会变得语义不唯一，所以这里必须尽早报错。
            if allBlocksByID.updateValue(block, forKey: block.id) != nil {
                throw SamoyedCoreError.duplicateBlockID(block.id)
            }
        }

        let activeBlocks = plan.blocks.filter { !$0.isCancelled }
        let activeBlocksByID = Dictionary(uniqueKeysWithValues: activeBlocks.map { ($0.id, $0) })
        var childrenByParent: [UUID?: [UUID]] = [:]

        for block in activeBlocks {
            // 注意：持久化形态是“扁平数组”，不是嵌套树。
            // 所以树结构约束要靠引擎主动检查，而不是靠 JSON 结构天然保证。
            if block.layerIndex == 0, block.parentBlockID != nil {
                throw SamoyedCoreError.invalidRootBlock(block.id)
            }

            if block.layerIndex > 0, block.parentBlockID == nil {
                throw SamoyedCoreError.invalidRootBlock(block.id)
            }

            if let parentID = block.parentBlockID, activeBlocksByID[parentID] == nil {
                throw SamoyedCoreError.missingParent(blockID: block.id, parentID: parentID)
            }

            childrenByParent[block.parentBlockID, default: []].append(block.id)
        }

        try detectCycles(in: activeBlocks, activeBlocksByID: activeBlocksByID)

        for block in activeBlocks {
            if block.layerIndex == 0 {
                // 基础块必须直接锚定在绝对时间轴上。
                if case .relative = block.timing {
                    throw SamoyedCoreError.baseBlockMustUseAbsoluteTiming(block.id)
                }
            } else if let parentID = block.parentBlockID, let parent = activeBlocksByID[parentID] {
                let expectedLayer = parent.layerIndex + 1
                if block.layerIndex != expectedLayer {
                    throw SamoyedCoreError.invalidLayerIndex(
                        blockID: block.id,
                        expected: expectedLayer,
                        actual: block.layerIndex
                    )
                }
            }
        }

        var resolvedRanges: [UUID: (start: Int, end: Int)] = [:]

        // 从根节点（`parentID == nil`）开始递归解析整棵块树。
        try resolveChildren(
            of: nil,
            in: activeBlocksByID,
            childrenByParent: childrenByParent,
            resolvedRanges: &resolvedRanges
        )

        return resolvedRanges
    }

    private static func detectCycles(
        in activeBlocks: [TimeBlock],
        activeBlocksByID: [UUID: TimeBlock]
    ) throws {
        // 由于每个 block 最多只有一个父节点，
        // 检测环不需要通用图算法，沿着 parent 指针一路向上走就够了。
        for block in activeBlocks {
            var visited: Set<UUID> = [block.id]
            var currentParentID = block.parentBlockID

            while let parentID = currentParentID {
                if !visited.insert(parentID).inserted {
                    throw SamoyedCoreError.cycleDetected(block.id)
                }

                currentParentID = activeBlocksByID[parentID]?.parentBlockID
            }
        }
    }

    private static func resolveChildren(
        of parentID: UUID?,
        in activeBlocksByID: [UUID: TimeBlock],
        childrenByParent: [UUID?: [UUID]],
        resolvedRanges: inout [UUID: (start: Int, end: Int)]
    ) throws {
        // 递归解析的单位不是“一个节点”，而是“同一父节点下的一组兄弟节点”。
        // 流程大致是：
        // 1. 先算出每个兄弟的理论开始时间
        // 2. 再结合父范围、下一个兄弟的开始、自己请求的结束，夹出真实结束时间
        // 3. 把结果写进 resolvedRanges
        // 4. 然后递归处理每个兄弟的子树
        let childIDs = childrenByParent[parentID] ?? []
        if childIDs.isEmpty {
            return
        }

        let parentRange: (start: Int, end: Int)?
        if let parentID {
            guard let resolvedParent = resolvedRanges[parentID] else {
                throw SamoyedCoreError.missingBlock(parentID)
            }
            parentRange = resolvedParent
        } else {
            parentRange = nil
        }

        let siblings = try childIDs.map { childID -> ResolvedSibling in
            guard let block = activeBlocksByID[childID] else {
                throw SamoyedCoreError.missingBlock(childID)
            }

            return try initialSiblingState(for: block, parentID: parentID, parentRange: parentRange)
        }
        .sorted { lhs, rhs in
            // 兄弟节点的稳定排序非常重要，
            // 因为“下一个兄弟的 start”会限制当前兄弟的 resolved end。
            if lhs.start != rhs.start {
                return lhs.start < rhs.start
            }
            return lhs.block.id.uuidString < rhs.block.id.uuidString
        }

        for index in siblings.indices {
            let sibling = siblings[index]
            let nextStart = siblings[safe: index + 1]?.start

            // 结束时间的上界来自三方面：
            // - 父块结束
            // - 下一个兄弟的开始
            // - 自己声明的 requested end/duration
            var upperBounds: [Int] = []
            if let parentRange {
                upperBounds.append(parentRange.end)
            } else {
                upperBounds.append(24 * 60)
            }
            if let nextStart {
                upperBounds.append(nextStart)
            }
            if let requestedEnd = sibling.requestedEnd {
                upperBounds.append(requestedEnd)
            }

            let resolvedEnd = upperBounds.min() ?? (24 * 60)
            let resolvedStart = sibling.start

            if let parentRange {
                // 子块必须完整落在父块区间内部。
                if resolvedStart < parentRange.start || resolvedStart >= parentRange.end {
                    throw SamoyedCoreError.blockOutsideParent(
                        blockID: sibling.block.id,
                        parentID: sibling.block.parentBlockID ?? parentID ?? sibling.block.id
                    )
                }
            }

            if resolvedStart >= resolvedEnd {
                throw SamoyedCoreError.invalidResolvedRange(
                    blockID: sibling.block.id,
                    start: resolvedStart,
                    end: resolvedEnd
                )
            }

            resolvedRanges[sibling.block.id] = (resolvedStart, resolvedEnd)
        }

        for sibling in siblings {
            try resolveChildren(
                of: sibling.block.id,
                in: activeBlocksByID,
                childrenByParent: childrenByParent,
                resolvedRanges: &resolvedRanges
            )
        }
    }

    private static func initialSiblingState(
        for block: TimeBlock,
        parentID: UUID?,
        parentRange: (start: Int, end: Int)?
    ) throws -> ResolvedSibling {
        // 这一步把两种 timing 统一归一成同一种中间表示：
        // - `start`
        // - `requestedEnd`
        // 这样后面的 sibling resolver 就不用分情况处理 absolute/relative 了。
        switch block.timing {
        case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay):
            guard (0 ..< 24 * 60).contains(startMinuteOfDay) else {
                throw SamoyedCoreError.invalidAbsoluteStart(
                    blockID: block.id,
                    minuteOfDay: startMinuteOfDay
                )
            }

            if let requestedEndMinuteOfDay, !(0 ... 24 * 60).contains(requestedEndMinuteOfDay) {
                throw SamoyedCoreError.invalidAbsoluteEnd(
                    blockID: block.id,
                    minuteOfDay: requestedEndMinuteOfDay
                )
            }

            if parentID == nil, block.layerIndex != 0 {
                throw SamoyedCoreError.invalidRootBlock(block.id)
            }

            return ResolvedSibling(
                block: block,
                start: startMinuteOfDay,
                requestedEnd: requestedEndMinuteOfDay
            )

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            guard let parentRange else {
                throw SamoyedCoreError.baseBlockMustUseAbsoluteTiming(block.id)
            }

            if let requestedDurationMinutes, requestedDurationMinutes <= 0 {
                throw SamoyedCoreError.invalidRelativeDuration(
                    blockID: block.id,
                    durationMinutes: requestedDurationMinutes
                )
            }

            // 相对块的 start = 父块起点 + offset；
            // 若给了 duration，则 requested end = start + duration。
            let start = parentRange.start + startOffsetMinutes
            let requestedEnd = requestedDurationMinutes.map { start + $0 }
            return ResolvedSibling(block: block, start: start, requestedEnd: requestedEnd)
        }
    }

    // MARK: - Runtime Blank Blocks

    private static func makeBlankBaseBlocks(in plan: DayPlan) -> [TimeBlock] {
        // 这里生成的是“运行时空白基础块”。
        // 它们的作用不是存档，而是把真实基础块之间的空档显式表达出来，
        // 这样 UI 可以像渲染普通块一样渲染空白时间。
        let resolvedBaseBlocks = plan.blocks
            .filter { !$0.isCancelled && $0.layerIndex == 0 }
            .sorted { lhs, rhs in
                let lhsStart = lhs.resolvedStartMinuteOfDay ?? 0
                let rhsStart = rhs.resolvedStartMinuteOfDay ?? 0
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        if resolvedBaseBlocks.isEmpty {
            return [blankBaseBlock(in: plan, start: 0, end: 24 * 60)]
        }

        var blanks: [TimeBlock] = []
        var cursor = 0

        for block in resolvedBaseBlocks {
            guard
                let start = block.resolvedStartMinuteOfDay,
                let end = block.resolvedEndMinuteOfDay
            else {
                continue
            }

            if cursor < start {
                blanks.append(blankBaseBlock(in: plan, start: cursor, end: start))
            }

            cursor = max(cursor, end)
        }

        if cursor < 24 * 60 {
            blanks.append(blankBaseBlock(in: plan, start: cursor, end: 24 * 60))
        }

        return blanks
    }

    private static func blankBaseBlock(in plan: DayPlan, start: Int, end: Int) -> TimeBlock {
        // `kind: .blankBase` 是识别这类运行时块的关键标记。
        TimeBlock(
            id: blankBaseBlockID(in: plan, start: start, end: end),
            dayPlanID: plan.id,
            layerIndex: 0,
            kind: .blankBase,
            title: "Blank",
            tasks: [],
            timing: .absolute(startMinuteOfDay: start, requestedEndMinuteOfDay: end),
            resolvedStartMinuteOfDay: start,
            resolvedEndMinuteOfDay: end
        )
    }

    private static func blankBaseBlockID(in plan: DayPlan, start: Int, end: Int) -> UUID {
        // 空白块 ID 不是随机生成，而是基于 plan + 区间稳定生成。
        // 这样同一个空白区间在反复解析时会得到同一个 ID，UI diff 会更稳定。
        let seed = "\(plan.id.uuidString)|\(start)|\(end)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func resolvedRangeMap(from blocks: [TimeBlock]) throws -> [UUID: (start: Int, end: Int)] {
        // 记录“编辑前”的解析区间快照，供结构性编辑后的回归检查使用。
        var ranges: [UUID: (start: Int, end: Int)] = [:]

        for block in blocks where !block.isCancelled {
            guard
                let start = block.resolvedStartMinuteOfDay,
                let end = block.resolvedEndMinuteOfDay
            else {
                throw SamoyedCoreError.invalidResolvedRange(blockID: block.id, start: -1, end: -1)
            }

            ranges[block.id] = (start, end)
        }

        return ranges
    }

    private static func validateCancelOverlapRisk(
        in plan: DayPlan,
        originalRanges: [UUID: (start: Int, end: Int)]
    ) throws {
        // 取消一个块以后，原来的子块可能被提升成新的兄弟节点。
        // 这里用“取消前”的区间来检查：这些新兄弟是否会彼此穿插重叠。
        let survivingBlocks = plan.blocks.filter { !$0.isCancelled }
        let groupedBlocks = Dictionary(grouping: survivingBlocks) { block in
            ParentLayerKey(parentID: block.parentBlockID, layerIndex: block.layerIndex)
        }

        for (_, blocks) in groupedBlocks {
            let sortedBlocks = try blocks.sorted { lhs, rhs in
                guard let lhsRange = originalRanges[lhs.id], let rhsRange = originalRanges[rhs.id] else {
                    throw SamoyedCoreError.missingBlock(lhs.id == rhs.id ? lhs.id : rhs.id)
                }

                if lhsRange.start != rhsRange.start {
                    return lhsRange.start < rhsRange.start
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            for index in sortedBlocks.indices.dropFirst() {
                let previous = sortedBlocks[index - 1]
                let current = sortedBlocks[index]

                guard
                    let previousRange = originalRanges[previous.id],
                    let currentRange = originalRanges[current.id]
                else {
                    throw SamoyedCoreError.missingBlock(previous.id)
                }

                if currentRange.start < previousRange.end {
                    throw SamoyedCoreError.cancelIntroducesSiblingOverlap(
                        firstBlockID: previous.id,
                        secondBlockID: current.id
                    )
                }
            }
        }
    }

    private static func validatePreservedRanges(
        after plan: DayPlan,
        against originalRanges: [UUID: (start: Int, end: Int)],
        excluding excludedIDs: Set<UUID>
    ) throws {
        // 除了被取消的那棵子树，其他 block 的 resolved range 不应该被悄悄改动。
        for block in plan.blocks where !block.isCancelled && !excludedIDs.contains(block.id) {
            guard let expectedRange = originalRanges[block.id] else {
                continue
            }

            guard
                let actualStart = block.resolvedStartMinuteOfDay,
                let actualEnd = block.resolvedEndMinuteOfDay
            else {
                throw SamoyedCoreError.invalidResolvedRange(blockID: block.id, start: -1, end: -1)
            }

            if actualStart != expectedRange.start || actualEnd != expectedRange.end {
                throw SamoyedCoreError.cancelChangesResolvedRange(
                    blockID: block.id,
                    expectedStart: expectedRange.start,
                    expectedEnd: expectedRange.end,
                    actualStart: actualStart,
                    actualEnd: actualEnd
                )
            }
        }
    }

    private static func buildChildrenMap(from blocks: [TimeBlock]) -> [UUID: [UUID]] {
        // 多次做图遍历时，先构建 parent -> children 索引会简单很多。
        var childrenByParent: [UUID: [UUID]] = [:]

        for block in blocks where !block.isCancelled {
            if let parentID = block.parentBlockID {
                childrenByParent[parentID, default: []].append(block.id)
            }
        }

        return childrenByParent
    }

    private static func parentStart(for block: TimeBlock, in activeBlocks: [TimeBlock]) -> Int {
        // 根块没有父块，因此它的“隐式父起点”就是 0:00。
        guard let parentBlockID = block.parentBlockID else {
            return 0
        }

        return activeBlocks
            .first(where: { $0.id == parentBlockID })?
            .resolvedStartMinuteOfDay ?? 0
    }

    private static func timingByMovingStart(
        of block: TimeBlock,
        to startMinuteOfDay: Int,
        preservingResolvedEndMinuteOfDay resolvedEndMinuteOfDay: Int,
        activeBlocks: [TimeBlock]
    ) throws -> TimeBlockTiming {
        // UI 手势关心的是“绝对分钟数”，
        // 但持久化层仍要保留用户原本是以 absolute 还是 relative 的方式定义这个块。
        // 所以这里负责把“移动后的绝对 start”重新翻译回合适的 `TimeBlockTiming`。
        switch block.timing {
        case let .absolute(_, requestedEndMinuteOfDay):
            return .absolute(
                startMinuteOfDay: startMinuteOfDay,
                requestedEndMinuteOfDay: requestedEndMinuteOfDay
            )

        case .relative:
            guard let parentBlockID = block.parentBlockID else {
                throw SamoyedCoreError.baseBlockMustUseAbsoluteTiming(block.id)
            }
            guard
                let parent = activeBlocks.first(where: { $0.id == parentBlockID }),
                let parentStart = parent.resolvedStartMinuteOfDay
            else {
                throw SamoyedCoreError.missingParent(blockID: block.id, parentID: parentBlockID)
            }

            return .relative(
                startOffsetMinutes: startMinuteOfDay - parentStart,
                requestedDurationMinutes: max(resolvedEndMinuteOfDay - startMinuteOfDay, 5)
            )
        }
    }

    private static func candidateStartPreservesResolvedEnd(
        _ candidateStartMinuteOfDay: Int,
        for target: TimeBlock,
        in resolvedPlan: DayPlan,
        activeBlocks: [TimeBlock]
    ) throws -> Bool {
        // 这里采用“模拟而不是手推公式”的策略。
        // 原因是 descendant overlay 的联动约束容易很复杂，
        // 直接构造一个临时 plan 再交给主解析器判断，反而更稳更容易维护。
        guard let currentResolvedEnd = target.resolvedEndMinuteOfDay else {
            throw SamoyedCoreError.invalidResolvedRange(blockID: target.id, start: -1, end: -1)
        }

        var candidatePlan = resolvedPlan
        guard let blockIndex = candidatePlan.blocks.firstIndex(where: { $0.id == target.id }) else {
            throw SamoyedCoreError.missingBlock(target.id)
        }
        candidatePlan.blocks[blockIndex].timing = try timingByMovingStart(
            of: target,
            to: candidateStartMinuteOfDay,
            preservingResolvedEndMinuteOfDay: currentResolvedEnd,
            activeBlocks: activeBlocks
        )

        let resolvedCandidatePlan = try resolved(candidatePlan)
        guard let updatedTarget = resolvedCandidatePlan.blocks.first(where: { $0.id == target.id }) else {
            throw SamoyedCoreError.missingBlock(target.id)
        }

        return updatedTarget.resolvedStartMinuteOfDay == candidateStartMinuteOfDay
            && updatedTarget.resolvedEndMinuteOfDay == currentResolvedEnd
    }

    private static func collectDescendants(
        startingAt blockID: UUID,
        childrenByParent: [UUID: [UUID]]
    ) -> Set<UUID> {
        // 用迭代版 DFS 收集整棵后代子树。
        var descendants: Set<UUID> = []
        var stack = childrenByParent[blockID] ?? []

        while let next = stack.popLast() {
            if descendants.insert(next).inserted {
                stack.append(contentsOf: childrenByParent[next] ?? [])
            }
        }

        return descendants
    }
}

private struct ResolvedSibling {
    // Lightweight intermediate state used while resolving one sibling group.
    let block: TimeBlock
    let start: Int
    let requestedEnd: Int?
}

private struct ParentLayerKey: Hashable {
    // Siblings are uniquely defined by sharing both a parent and a layer.
    let parentID: UUID?
    let layerIndex: Int
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
