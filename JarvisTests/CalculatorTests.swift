import XCTest
@testable import Jarvis

final class CalculatorTests: XCTestCase {
    func testSplitBillWithTax() throws {
        let calculator = Calculator()
        let result = try calculator.evaluate("split $126.40 among 3 with tax 9.75%")
        XCTAssertEqual(result.expression, result.expression)
        let doubleValue = NSDecimalNumber(decimal: result.result).doubleValue
        XCTAssertEqual(doubleValue, 46.33, accuracy: 0.5)
        XCTAssertFalse(result.steps.isEmpty)
    }

    func testBasicExpression() throws {
        let calculator = Calculator()
        let result = try calculator.evaluate("2 + 2 * 3")
        XCTAssertEqual(NSDecimalNumber(decimal: result.result).doubleValue, 8)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
