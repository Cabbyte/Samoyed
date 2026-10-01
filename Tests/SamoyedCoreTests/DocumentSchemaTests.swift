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
            ["dayPlans", "savedTemplates", "weekdayRules", "overrides", "daySelections", "timelineNotes"]
        )
    }
}

extension DocumentSchemaTests {
    func testRoutineGuidanceAcceptsNewNameAndRetainsLegacyFileEncoding() throws {
        let block = BlockTemplate(layerIndex: 0, title: "Morning", note: "Old guidance", timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 600))
        let original = try JSONEncoder().encode(block)
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        value["guidance"] = "Nest guidance"
        let decoded = try JSONDecoder().decode(BlockTemplate.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertEqual(decoded.note, "Nest guidance")
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertEqual(encoded["note"] as? String, "Nest guidance")
        XCTAssertNil(encoded["guidance"])
    }
}
