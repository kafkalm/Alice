import XCTest
@testable import AliceCore

final class NLTokenizerSentenceSplitterTests: XCTestCase {
    func testSplitParagraphIntoSentences() {
        let splitter = NLTokenizerSentenceSplitter()
        let paragraph = "The manager approved the budget. She sent an update to the team. Everyone aligned on the plan."

        let result = splitter.split(paragraph)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "The manager approved the budget.")
        XCTAssertEqual(result[1], "She sent an update to the team.")
        XCTAssertEqual(result[2], "Everyone aligned on the plan.")
    }
}
