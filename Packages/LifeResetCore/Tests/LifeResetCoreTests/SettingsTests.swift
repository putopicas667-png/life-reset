import XCTest
@testable import LifeResetCore

final class SettingsTests: XCTestCase {
    func testInitialProfileMatchesSpecification() {
        let p = ProfileSettings.initial
        XCTAssertEqual(p.wake, TimeOfDay(7, 30))
        XCTAssertEqual(p.bed.wrapped, TimeOfDay(0, 0))
        XCTAssertEqual(p.startWeightKg, 50)
        XCTAssertEqual(p.targetWeightKg, 65)
        XCTAssertEqual(p.dailyKcal, 2800)
        XCTAssertEqual(p.dailyWaterMl, 3000)
        XCTAssertEqual(p.mainMeals, 3)
        XCTAssertEqual(p.workoutsPerWeek, 4)
        XCTAssertEqual(p.maxRecoveryDays, 2)
        XCTAssertEqual(p.currencyCode, "CHF")
        XCTAssertTrue(p.validationIssues().isEmpty)
    }

    func testBurgerJobDerivedTimes() {
        let j = JobSettings.burgerInitial
        XCTAssertTrue(j.validationIssues().isEmpty)
        XCTAssertEqual(j.preShiftWindow, 30)
        XCTAssertEqual(j.commuteToWork, 40)
        XCTAssertEqual(j.commuteHome, 30)
        XCTAssertEqual(j.shiftDuration, 12 * 60)
        XCTAssertEqual(j.breakMinutes, 60)
        XCTAssertEqual(j.shiftsPerWeek, 4)
    }

    func testCafeJobIsSundayWithShortBreak() {
        let j = JobSettings.cafeInitial
        XCTAssertTrue(j.validationIssues().isEmpty)
        XCTAssertEqual(j.fixedWeekday, 1)
        XCTAssertEqual(j.breakMinutes, 30)
        XCTAssertEqual(j.preShiftWindow, 0)
        XCTAssertEqual(j.commuteHome, 90)
    }

    func testInvalidJobIsReported() {
        var j = JobSettings.burgerInitial
        j.end = TimeOfDay(9, 0)
        j.breakMinutes = 900
        XCTAssertFalse(j.validationIssues().isEmpty)
    }

    func testRecoveryLimitCannotExceedTwo() {
        var p = ProfileSettings.initial
        p.maxRecoveryDays = 3
        XCTAssertTrue(p.validationIssues().contains { $0.contains("Recovery") })
    }

    func testDayPeriods() {
        XCTAssertEqual(DayPeriod.at(TimeOfDay(8)), .morning)
        XCTAssertEqual(DayPeriod.at(TimeOfDay(15)), .afternoon)
        XCTAssertEqual(DayPeriod.at(TimeOfDay(21)), .evening)
        XCTAssertEqual(DayPeriod.at(TimeOfDay(2)), .night)
        XCTAssertEqual(DayPeriod.at(TimeOfDay(24, 30)), .night)
    }
}
