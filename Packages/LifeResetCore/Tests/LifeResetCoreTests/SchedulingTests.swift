import XCTest
@testable import LifeResetCore

final class SchedulingTests: XCTestCase {
    let cal = LRCalendar.current
    // 2026-11-16 é segunda-feira
    lazy var monday: Date = cal.date(from: DateComponents(year: 2026, month: 11, day: 16))!

    func burgerDay(_ date: Date, overtime: Int = 0, recovery: Bool = false) -> DayInfo {
        var d = DayInfo.work(.burgerInitial, on: date, breakStart: TimeOfDay(16, 0), overtime: overtime)
        d.isRecovery = recovery
        return d
    }

    func testWeekStartIsMonday() {
        let thursday = LRCalendar.addDays(3, to: monday)
        XCTAssertEqual(LRCalendar.weekStart(for: thursday), monday)
        let sunday = LRCalendar.addDays(6, to: monday)
        XCTAssertEqual(LRCalendar.weekStart(for: sunday), monday)
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1)
    }

    func testRecurrences() {
        XCTAssertTrue(Recurrence.daily.occurs(on: monday))
        XCTAssertTrue(Recurrence.weekly(weekdays: [2, 4]).occurs(on: monday))
        XCTAssertFalse(Recurrence.weekly(weekdays: [3]).occurs(on: monday))
        XCTAssertEqual(Recurrence.everyNDays(n: 3, anchor: monday).dates(from: monday, to: LRCalendar.addDays(9, to: monday)).count, 4)
        let lastDay = cal.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        XCTAssertTrue(Recurrence.monthly(day: 0).occurs(on: lastDay))
        XCTAssertTrue(Recurrence.monthly(day: 31).occurs(on: lastDay))
    }

    func testBurgerDayContext() {
        let ctx = DayContextBuilder.build(burgerDay(monday), next: nil, profile: .initial)
        XCTAssertEqual(ctx.commuteOut, TimeRange(TimeOfDay(9, 20), TimeOfDay(10, 0)))
        XCTAssertEqual(ctx.preShift, TimeRange(TimeOfDay(10, 0), TimeOfDay(10, 30)))
        XCTAssertEqual(ctx.work, TimeRange(TimeOfDay(10, 30), TimeOfDay(22, 30)))
        XCTAssertEqual(ctx.workBreak, TimeRange(TimeOfDay(16, 0), TimeOfDay(17, 0)))
        XCTAssertEqual(ctx.wake, TimeOfDay(7, 30)) // 09:20 − 60 min = 08:20 > 07:30
        XCTAssertEqual(ctx.homeWindows.first, TimeRange(TimeOfDay(7, 30), TimeOfDay(9, 20)))
        XCTAssertEqual(ctx.homeWindows.last, TimeRange(TimeOfDay(23, 0), TimeOfDay(24, 0)))
    }

    func testOvertimePushesReturnAndWarns() {
        let ctx = DayContextBuilder.build(burgerDay(monday, overtime: 60), next: nil, profile: .initial)
        XCTAssertEqual(ctx.work?.end, TimeOfDay(23, 30))
        XCTAssertEqual(ctx.commuteBack?.end, TimeOfDay(24, 0))
        XCTAssertFalse(ctx.warnings.isEmpty)
    }

    func testEarlyNextDayWarning() {
        var profile = ProfileSettings.initial
        profile.wake = TimeOfDay(9, 0)
        let off = DayInfo(date: monday, kind: .dayOff)
        let ctx = DayContextBuilder.build(off, next: burgerDay(LRCalendar.addDays(1, to: monday)), profile: profile)
        XCTAssertTrue(ctx.warnings.contains { $0.contains("Amanhã tens de acordar às 08:20") })
    }

    func testPlannerKeepsHomeTasksAtHomeAndBreakTasksInBreak() {
        let ctx = DayContextBuilder.build(burgerDay(monday), next: nil, profile: .initial)
        let vacuum = PlanTask(title: "Aspirar", minutes: 30, priority: 2, timing: .flexible(earliest: TimeOfDay(8), latest: TimeOfDay(22)), location: .home)
        let water = PlanTask(title: "Registar refeição", minutes: 5, priority: 3, timing: .flexible(earliest: TimeOfDay(10), latest: TimeOfDay(22)), location: .breakCompatible)
        let teeth = PlanTask(title: "Escovar dentes", minutes: 3, timing: .anchored(.afterLunch), location: .anywhere, essential: true)
        let plan = DayPlanner.plan(context: ctx, tasks: [vacuum, water, teeth], meals: MealTiming.slots(for: ctx))
        let v = plan.start(of: vacuum.id)!
        XCTAssertTrue(ctx.homeWindows.contains { $0.contains(v) }, "Aspirar tem de ficar em casa")
        let w = plan.start(of: water.id)!
        XCTAssertTrue(ctx.breakWindows.contains { $0.contains(w) }, "Pequena tarefa vai para a pausa ou pré-turno")
        XCTAssertEqual(plan.start(of: teeth.id), TimeOfDay(16, 0))
        XCTAssertTrue(plan.conflicts.isEmpty)
    }

    func testFixedTaskConflictIsReportedNotMoved() {
        let ctx = DayContextBuilder.build(burgerDay(monday), next: nil, profile: .initial)
        let dentist = PlanTask(title: "Dentista", minutes: 60, priority: 1, timing: .fixed(TimeOfDay(15, 0)), location: .home)
        let plan = DayPlanner.plan(context: ctx, tasks: [dentist])
        XCTAssertEqual(plan.start(of: dentist.id), TimeOfDay(15, 0))
        XCTAssertEqual(plan.conflicts.count, 1)
    }

    func testRecoveryKeepsOnlyEssentials() {
        let ctx = DayContextBuilder.build(DayInfo(date: monday, kind: .dayOff, isRecovery: true), next: nil, profile: .initial)
        let face = PlanTask(title: "Lavar a cara", minutes: 3, timing: .anchored(.morning), essential: true)
        let gym = PlanTask(title: "Treino completo", minutes: 60, timing: .flexible(earliest: TimeOfDay(9), latest: TimeOfDay(21)), essential: true, heavy: true)
        let clean = PlanTask(title: "Limpar pó", minutes: 20, timing: .flexible(earliest: TimeOfDay(9), latest: TimeOfDay(21)))
        let plan = DayPlanner.plan(context: ctx, tasks: [face, gym, clean])
        XCTAssertNotNil(plan.start(of: face.id))
        XCTAssertNil(plan.start(of: gym.id))
        XCTAssertNil(plan.start(of: clean.id))
        XCTAssertEqual(plan.unplaced.filter { $0.reason == "Recovery Mode" }.count, 2)
    }

    func testTravelSkipsHomeTasks() {
        let ctx = DayContextBuilder.build(DayInfo(date: monday, kind: .travel), next: nil, profile: .initial)
        let laundry = PlanTask(title: "Lavandaria", minutes: 60, timing: .flexible(earliest: TimeOfDay(9), latest: TimeOfDay(21)), location: .home)
        let teeth = PlanTask(title: "Escovar dentes", minutes: 3, timing: .anchored(.morning), location: .anywhere, essential: true)
        let plan = DayPlanner.plan(context: ctx, tasks: [laundry, teeth])
        XCTAssertNil(plan.start(of: laundry.id))
        XCTAssertNotNil(plan.start(of: teeth.id))
    }

    func testShiftChangeProducesProposals() {
        let p = ProfileSettings.initial
        let task = PlanTask(title: "Lavar loiça", minutes: 20, priority: 2, timing: .flexible(earliest: TimeOfDay(10), latest: TimeOfDay(23, 30)))
        let off = DayPlanner.plan(context: DayContextBuilder.build(DayInfo(date: monday, kind: .dayOff), next: nil, profile: p), tasks: [task])
        let work = DayPlanner.plan(context: DayContextBuilder.build(burgerDay(monday), next: nil, profile: p), tasks: [task])
        let changes = PlanDiff.changes(from: off, to: work)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.taskId, task.id)
    }

    func testWeekValidation() {
        let days = LRCalendar.days(ofWeekStarting: monday)
        var week: [DayInfo] = []
        for (i, d) in days.enumerated() {
            switch i {
            case 0, 1, 3, 4: week.append(burgerDay(d))
            case 6: week.append(DayInfo.work(.cafeInitial, on: d))
            default: week.append(DayInfo(date: d, kind: .dayOff))
            }
        }
        XCTAssertFalse(WeekValidator.hasErrors(WeekValidator.validate(week)))
        XCTAssertTrue(WeekValidator.validate(week).isEmpty)
        week[2].isRecovery = true; week[5].isRecovery = true; week[0].isRecovery = true
        XCTAssertTrue(WeekValidator.hasErrors(WeekValidator.validate(week)))
    }

    func testRolloverPolicies() {
        let today = monday
        XCTAssertEqual(Rollover.decide(policy: .carryToNextPeriod, deadline: nil, today: today), .markFailed)
        XCTAssertEqual(Rollover.decide(policy: .proposeReschedule, deadline: nil, today: today), .markFailedAndPropose)
        XCTAssertEqual(Rollover.decide(policy: .keepDeadline, deadline: LRCalendar.addDays(2, to: today), today: today), .keepPending)
        XCTAssertEqual(Rollover.decide(policy: .keepDeadline, deadline: LRCalendar.addDays(-1, to: today), today: today), .markFailed)
    }

    func testQuickEntry() {
        let d = QuickEntryParser.parse("comprar champô amanhã", now: monday)
        XCTAssertEqual(d.title, "Comprar champô")
        XCTAssertEqual(d.day, LRCalendar.addDays(1, to: monday))
        XCTAssertEqual(d.category, "shopping")

        let e = QuickEntryParser.parse("Pagar renda sexta às 18h", now: monday)
        XCTAssertEqual(e.title, "Pagar renda")
        XCTAssertEqual(e.time, TimeOfDay(18))
        XCTAssertEqual(cal.component(.weekday, from: e.day!), 6)
        XCTAssertEqual(e.category, "finance")
    }

    func testMealsOnCafeDay() {
        let sunday = LRCalendar.addDays(6, to: monday)
        let ctx = DayContextBuilder.build(DayInfo.work(.cafeInitial, on: sunday, breakStart: TimeOfDay(17)), next: nil, profile: .initial)
        let meals = MealTiming.slots(for: ctx)
        XCTAssertEqual(meals.count, 3)
        XCTAssertTrue(meals[1].range.end <= TimeOfDay(12, 50), "Almoço antes de sair às 12:50")
        XCTAssertEqual(meals[2].range.start, TimeOfDay(22, 0))
    }
}
