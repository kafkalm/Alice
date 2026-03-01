import XCTest
@testable import AliceCore

final class HeuristicSVOParserTests: XCTestCase {
    func testParseSimpleSentence() {
        let parser = HeuristicSVOParser()

        let result = parser.parse(
            ParseSentenceRequest(
                sentence: "The manager approved the revised budget yesterday.",
                mode: .local,
                contextId: "ctx-1"
            )
        )

        XCTAssertEqual(result.subject.lowercased(), "manager")
        XCTAssertEqual(result.verb.lowercased(), "approved")
        XCTAssertEqual(result.object.lowercased(), "budget")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testParsePronounSubjectSentence() {
        let parser = HeuristicSVOParser()

        let result = parser.parse(
            ParseSentenceRequest(
                sentence: "She reads novels at night.",
                mode: .local,
                contextId: "ctx-2"
            )
        )

        XCTAssertEqual(result.subject.lowercased(), "she")
        XCTAssertEqual(result.verb.lowercased(), "reads")
        XCTAssertEqual(result.object.lowercased(), "novels")
    }

    func testLowConfidenceWhenVerbMissing() {
        let parser = HeuristicSVOParser()

        let result = parser.parse(
            ParseSentenceRequest(
                sentence: "A complex project with many stakeholders.",
                mode: .local,
                contextId: "ctx-3"
            )
        )

        XCTAssertTrue(result.verb.isEmpty)
        XCTAssertLessThan(result.confidence, 0.6)
    }
}
