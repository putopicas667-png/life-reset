import XCTest
@testable import LifeResetCore

final class FinanceHealthTests: XCTestCase {
    func testParseAmount() {
        XCTAssertEqual(FinanceMath.parseAmount("12,50"), Decimal(string: "12.5"))
        XCTAssertEqual(FinanceMath.parseAmount("1'234.50"), Decimal(string: "1234.5"))
        XCTAssertEqual(FinanceMath.parseAmount("1.234,50"), Decimal(string: "1234.5"))
        XCTAssertEqual(FinanceMath.parseAmount("-8.90 CHF"), Decimal(string: "-8.9"))
        XCTAssertNil(FinanceMath.parseAmount("Migros"))
    }

    func testForecast() {
        let f = FinanceMath.forecast(income: 3000, spent: 1000, variableSpent: 300, fixed: [
            .init(amount: 550, dayOfMonth: 1, paid: true), .init(amount: 60, dayOfMonth: 20, paid: false),
        ], day: 10, daysInMonth: 30)
        XCTAssertEqual(f.fixedPending, 60)
        XCTAssertEqual(f.variableProjection, 600)
        XCTAssertEqual(f.endBalance, 3000 - 1000 - 60 - 600)
    }

    func testMilestonesAndDebt() {
        XCTAssertEqual(FinanceMath.milestonesReached(saved: 500, target: 1000), 2)
        XCTAssertEqual(FinanceMath.milestonesReached(saved: 1000, target: 1000), 4)
        XCTAssertEqual(FinanceMath.remaining(initial: 100, payments: [30, 80]), 0)
    }

    func testCSVSemicolonWithHeader() {
        let csv = "Data;Descrição;Montante\n01.11.2026;Migros Genève;-45,30\n02.11.2026;Salário;3200,00\nlixo;x;y\n"
        let r = CSVImport.parse(csv)
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertEqual(r.rows[0].amount, Decimal(string: "-45.3"))
        XCTAssertEqual(r.rows[0].description, "Migros Genève")
        XCTAssertEqual(CSVImport.suggestCategory(r.rows[0].description), "Alimentação")
    }

    func testCSVDebitCredit() {
        let csv = "Date,Text,Debit,Credit\n2026-11-03,SBB CFF,12.40,\n2026-11-04,Twint,,50.00\n"
        let r = CSVImport.parse(csv)
        XCTAssertEqual(r.rows.map(\.amount), [Decimal(string: "-12.4")!, 50])
    }

    func testTrainingProgression() {
        let ok = [TrainingRules.SetResult(reps: 8, kg: 40), .init(reps: 8, kg: 40)]
        XCTAssertEqual(TrainingRules.suggestedKg(last: ok, targetReps: 8), 42.5)
        let short = [TrainingRules.SetResult(reps: 8, kg: 40), .init(reps: 6, kg: 40)]
        XCTAssertEqual(TrainingRules.suggestedKg(last: short, targetReps: 8), 40)
        XCTAssertEqual(TrainingRules.suggestedKg(last: [.init(reps: 12, kg: 8)], targetReps: 10), 9)
    }

    func testRecipeMatcher() {
        let m = RecipeMatcher.rank([("A", ["Massa", "Frango"]), ("B", ["Arroz", "Atum"])], pantry: ["massa", "Peito de frango"])
        XCTAssertEqual(m.first?.name, "A")
        XCTAssertEqual(m.first?.missing, [])
    }

    func testWeight() {
        XCTAssertEqual(WeightMath.movingAverage([1, 2, 3], window: 2), [1, 1.5, 2.5])
        let d0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(WeightMath.weeklyTrend([(d0, 50), (d0.addingTimeInterval(14 * 86_400), 51)])!, 0.5, accuracy: 0.001)
    }
}
