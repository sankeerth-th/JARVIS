import XCTest
@testable import Jarvis

final class TableExtractorTests: XCTestCase {
    func testMarkdownExtraction() throws {
        let sample = "Name,Amount\nAlpha,10\nBeta,20"
        let extractor = TableExtractor()
        let result = extractor.extract(from: sample)
        XCTAssertEqual(result.headers, ["Name", "Amount"])
        XCTAssertEqual(result.rows.count, 2)
        let markdown = try extractor.render(result, format: .markdown)
        XCTAssertTrue(markdown.contains("| Name | Amount |"))
    }
}
