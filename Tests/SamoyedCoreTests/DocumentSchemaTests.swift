import Foundation
import XCTest
@testable import SamoyedCore

final class DocumentSchemaTests: XCTestCase {
    func testFixtureDecodeEncodeDecodePreservesDocumentSchema() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "document", withExtension: "json", subdirectory: "Fixtures")
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        let document = try decoder.decode(SamoyedDocument.self, from: fixtureData)

        let encoded = try JSONEncoder().encode(document)
        let roundTripped = try decoder.decode(SamoyedDocument.self, from: encoded)

        XCTAssertEqual(roundTripped, document)
        XCTAssertEqual(document.dayPlans.first?.blocks.first?.kind, .userDefined)
        XCTAssertEqual(document.dayPlans.first?.blocks.first?.reminders.first?.triggerMode, .beforeStart)
        XCTAssertEqual(document.weekdayRules.first?.weekday, .wednesday)
        XCTAssertEqual(document.daySelections.first?.source, .pickedTemplate)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            [
                "dayPlans", "savedTemplates", "weekdayRules", "overrides", "daySelections",
                "feedbackEvents", "suggestions", "routineRevisionSnapshots", "plannerSettings"
            ]
        )
    }
}
