import XCTest
@testable import ShoppingCore

final class LockerPickupTests: XCTestCase {
    let text = """
    Costco Pharmacy #00106,AURORA VILLAGE: LOCKER ORDER
    (206) 555-0100

    For: ALISE
    Pickup Code: AVQHTH
    Code is required to open the locker. Please pick-up within 5 days.

    Pickup is available during warehouse hours, including Sunday. Rx Pickup Lockers are located near the warehouse exit.
    """

    func testReadsThePharmacysText() {
        XCTAssertEqual(LockerPickup.parse(text), LockerPickup(code: "AVQHTH", name: "Alise", days: 5))
    }

    func testReadsItPastedOnOneLine() {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        XCTAssertEqual(LockerPickup.parse(line), LockerPickup(code: "AVQHTH", name: "Alise", days: 5))
    }

    func testOtherTextIsNotAPickup() {
        XCTAssertNil(LockerPickup.parse("Paper towels"))
        XCTAssertNil(LockerPickup.parse("Your prescription is ready. Please pick-up within 5 days."))
    }

    func testNote() {
        let note = LockerPickup(code: "AVQHTH", name: "Alise", days: 5).note(receivedAt: Date())
        XCTAssertTrue(note.hasPrefix("Code AVQHTH · Alise · by "), note)
        XCTAssertEqual(LockerPickup(code: "AB12").note(receivedAt: Date()), "Code AB12")
    }
}
