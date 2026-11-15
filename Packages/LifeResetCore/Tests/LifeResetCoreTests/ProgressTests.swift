import XCTest
@testable import LifeResetCore

final class ProgressTests: XCTestCase {
    func testAchievementsUnlockOnceAndNeverDuplicate() {
        var s = LifeStats()
        s.tasksDone = 60; s.workouts = 1
        let first = Achievements.newlyUnlocked(stats: s, already: [])
        XCTAssertTrue(first.map(\.id).contains("first-task"))
        XCTAssertTrue(first.map(\.id).contains("tasks-50"))
        XCTAssertTrue(first.map(\.id).contains("workout-1"))
        XCTAssertFalse(first.map(\.id).contains("tasks-250"))
        let again = Achievements.newlyUnlocked(stats: s, already: Set(first.map(\.id)))
        XCTAssertTrue(again.isEmpty)
    }

    func testInsightsCompareDayKinds() {
        let start = LRCalendar.weekStart(for: Date())
        var recs: [Insights.DayRecord] = []
        for i in 0..<14 {
            let d = LRCalendar.addDays(-i, to: start)
            let kind: DayKind = i % 2 == 0 ? .burgerShift : .dayOff
            recs.append(.init(date: d, kind: kind, done: kind == .dayOff ? 9 : 5, total: 10))
        }
        let msgs = Insights.messages(recs)
        XCTAssertTrue(msgs.contains { $0.contains("90 %") && $0.contains("folga") }, "\(msgs)")
    }
}
