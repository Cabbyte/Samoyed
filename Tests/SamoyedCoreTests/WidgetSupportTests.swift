import XCTest
@testable import SamoyedCore

final class WidgetSupportTests: XCTestCase {
    func testLocalDayParsesISODateString() {
        let day = LocalDay(isoDateString: "2026-03-22")

        XCTAssertEqual(day, LocalDay(year: 2026, month: 3, day: 22))
        XCTAssertNil(LocalDay(isoDateString: "2026/03/22"))
    }

    func testWidgetSnapshotPrioritizesCurrentSectionTasksAndCountsRemaining() {
        let currentBlockID = UUID()
        let baseBlockID = UUID()
        let model = NowScreenModel(
            date: LocalDay(year: 2026, month: 3, day: 22),
            minuteOfDay: 600,
            activeChain: [
                NowChainItem(
                    id: currentBlockID,
                    title: "Focus Sprint",
                    layerIndex: 1,
                    startMinuteOfDay: 540,
                    endMinuteOfDay: 660,
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
                ),
                NowChainItem(
                    id: baseBlockID,
                    title: "Morning",
                    layerIndex: 0,
                    startMinuteOfDay: 480,
                    endMinuteOfDay: 720,
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                )
            ],
            currentBlockTitle: "Focus Sprint",
            noteSections: [],
            statusMessage: nil,
            taskSourceTitle: "Focus Sprint",
            taskSections: [
                NowTaskSection(
                    id: baseBlockID,
                    title: "Morning",
                    layerIndex: 0,
                    startMinuteOfDay: 480,
                    endMinuteOfDay: 720,
                    tasks: [task("Base task")],
                    isCurrent: false,
                    isTaskSource: false,
                    isComplete: false
                ),
                NowTaskSection(
                    id: currentBlockID,
                    title: "Focus Sprint",
                    layerIndex: 1,
                    startMinuteOfDay: 540,
                    endMinuteOfDay: 660,
                    tasks: [
                        task("Completed first", completed: true),
                        task("Current next", order: 1)
                    ],
                    isCurrent: true,
                    isTaskSource: true,
                    isComplete: false
                )
            ]
        )

        let snapshot = SamoyedWidgetSnapshotBuilder.makeSnapshot(
            from: model,
            maxTaskCount: 3
        )

        XCTAssertEqual(snapshot.currentBlockTitle, "Focus Sprint")
        XCTAssertEqual(snapshot.currentBlockTimeRangeText, "09:00 - 11:00")
        XCTAssertEqual(snapshot.blocks.map { $0.title }, ["Focus Sprint", "Morning"])
        XCTAssertEqual(snapshot.blocks.map { $0.layerIndex }, [1, 0])
        XCTAssertTrue(snapshot.blocks.first?.isCurrent == true)
        XCTAssertEqual(snapshot.remainingTaskCount, 2)
        XCTAssertEqual(snapshot.state, .active)
        XCTAssertEqual(snapshot.tasks.map { $0.title }, ["Current next", "Base task"])
        XCTAssertEqual(snapshot.tasks.map { $0.blockTitle }, ["Focus Sprint", "Morning"])
        XCTAssertEqual(snapshot.tasks.map { $0.layerIndex }, [1, 0])
        XCTAssertTrue(snapshot.tasks.allSatisfy { !$0.isCompleted })
    }

    func testRepositoryWidgetSnapshotUsesNoRoutineStateWhenTodayHasNoSelection() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "SamoyedTests")
            .appending(path: "\(UUID().uuidString).json")
        let repository = SamoyedDocumentRepository(fileURL: fileURL)

        try repository.save(SamoyedDocument())

        let snapshot = try repository.widgetSnapshot(
            at: try XCTUnwrap(day.date(minuteOfDay: 600)),
            maxTaskCount: 3
        )

        XCTAssertEqual(snapshot.state, .needsSetup)
        XCTAssertTrue(snapshot.blocks.isEmpty)
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertEqual(snapshot.statusMessage, "Choose today’s routine")
    }

    func testWidgetSnapshotSeparatesCaughtUpFromUnavailable() {
        let blockID = UUID()
        let caughtUp = SamoyedWidgetSnapshotBuilder.makeSnapshot(
            from: NowScreenModel(
                date: LocalDay(year: 2026, month: 3, day: 22),
                minuteOfDay: 600,
                activeChain: [
                    NowChainItem(
                        id: blockID,
                        title: "Focus",
                        layerIndex: 0,
                        startMinuteOfDay: 540,
                        endMinuteOfDay: 660,
                        isBlank: false,
                        hasIncompleteTasks: false,
                        isCurrent: true
                    )
                ],
                currentBlockTitle: "Focus",
                noteSections: [],
                statusMessage: nil,
                taskSourceTitle: nil,
                taskSections: [],
                focusState: .active
            ),
            maxTaskCount: 3
        )
        let unavailable = SamoyedWidgetSnapshotBuilder.makeSnapshot(
            from: NowScreenModel(
                date: LocalDay(year: 2026, month: 3, day: 22),
                minuteOfDay: 720,
                activeChain: [],
                currentBlockTitle: nil,
                noteSections: [],
                statusMessage: "Open time",
                taskSourceTitle: nil,
                taskSections: [],
                focusState: .openTime
            ),
            maxTaskCount: 3
        )

        XCTAssertEqual(caughtUp.state, .caughtUp)
        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertEqual(unavailable.statusMessage, "Open time")
    }

    func testWidgetTimelineUsesNumericBlockBoundaryBeforeFallback() throws {
        let day = LocalDay(year: 2026, month: 3, day: 22)
        let referenceDate = try XCTUnwrap(day.date(minuteOfDay: 600))
        let snapshot = SamoyedWidgetSnapshot(
            date: day,
            minuteOfDay: 600,
            state: .active,
            currentBlockTitle: "Focus",
            currentBlockTimeRangeText: "10:00 - 10:05",
            blocks: [
                SamoyedWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Focus",
                    layerIndex: 0,
                    timeRangeText: "10:00 - 10:05",
                    endMinuteOfDay: 605,
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
                )
            ],
            remainingTaskCount: 1,
            tasks: [],
            statusMessage: nil
        )

        XCTAssertEqual(
            SamoyedWidgetSnapshotBuilder.nextRefreshDate(for: snapshot, referenceDate: referenceDate),
            try XCTUnwrap(day.date(minuteOfDay: 605))
        )
    }
}
