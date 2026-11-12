import XCTest
@testable import ShoppingCore

final class NotHereTests: XCTestCase {
    func testMarkedRowsMoveToNotHereInOrder() {
        var marks = NotHereMarks()
        marks.mark("b")
        marks.mark("d")
        let split = marks.split(["a", "b", "c", "d"]) { $0 }
        XCTAssertEqual(split.inPlay, ["a", "c"])
        XCTAssertEqual(split.notHere, ["b", "d"])
    }

    func testUnmarkingPutsItBackAndNilIsNeverMarked() {
        var marks = NotHereMarks(["b"])
        marks.mark(nil)
        XCTAssertFalse(marks.contains(nil))
        marks.unmark("b")
        XCTAssertEqual(marks.split(["a", "b"]) { $0 }.notHere, [])
    }
}
