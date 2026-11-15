import XCTest
@testable import LifeResetCore

final class TimeOfDayTests: XCTestCase {
    func testParsingFormats() {
        XCTAssertEqual(TimeOfDay(parsing: "09:20"), TimeOfDay(9, 20))
        XCTAssertEqual(TimeOfDay(parsing: "9:20"), TimeOfDay(9, 20))
        XCTAssertEqual(TimeOfDay(parsing: "18h"), TimeOfDay(18))
        XCTAssertEqual(TimeOfDay(parsing: "18h30"), TimeOfDay(18, 30))
        XCTAssertNil(TimeOfDay(parsing: "25:99"))
        XCTAssertNil(TimeOfDay(parsing: "abc"))
    }

    func testAfterMidnightIsOrderedAfterEvening() {
        let leaveWork = TimeOfDay(22, 30)
        let home = TimeOfDay(24, 30) // 00:30 do dia seguinte
        XCTAssertLessThan(leaveWork, home)
        XCTAssertEqual(home.description, "00:30")
        XCTAssertEqual(leaveWork.minutes(until: home), 120)
    }

    func testRangesOverlap() {
        let shift = TimeRange(TimeOfDay(10, 30), TimeOfDay(22, 30))
        let pause = TimeRange(TimeOfDay(15), TimeOfDay(16))
        let commute = TimeRange(TimeOfDay(9, 20), TimeOfDay(10))
        XCTAssertTrue(shift.contains(pause))
        XCTAssertFalse(shift.overlaps(commute))
        XCTAssertEqual(shift.duration, 12 * 60)
    }
}
