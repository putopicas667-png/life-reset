import Foundation
import SwiftData
import LifeResetCore

/// Esquema v2: acrescenta todos os modelos das fases 2–8 (o perfil e os trabalhos vêm do v1, sem alterações).
/// A migração v1 → v2 é "lightweight" (só entidades novas).
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SchemaV1.UserProfile.self, SchemaV1.Job.self,
         WeekPlan.self, DayAssignment.self, TaskItem.self, TaskOccurrence.self, DailyPriority.self, RescheduleSuggestion.self,
         FoodItem.self, MealEntry.self, WaterEntry.self, WeightEntry.self, BodyMeasurement.self, ProgressPhoto.self,
         PantryItem.self, ShoppingItem.self, Recipe.self, PersonalProduct.self,
         Exercise.self, WorkoutTemplate.self, WorkoutSession.self,
         Account.self, IncomeEntry.self, Expense.self, ExpenseCategory.self, FixedExpense.self, Budget.self,
         Debt.self, DebtPayment.self, SavingsGoal.self, SavingsContribution.self, MonthlyReport.self,
         XPEvent.self, Goal.self, AchievementUnlock.self,
         CalendarEvent.self, Trip.self, Flight.self, ChecklistTemplate.self, TripChecklistItem.self,
         TimeLog.self, AppMeta.self]
    }

    // MARK: Semana e turnos
    @Model final class WeekPlan {
        var weekStart: Date = Date.distantPast
        var confirmed: Bool = false
        var priorities: [String] = []
        var trainingNotes: String = ""
        var shoppingNotes: String = ""
        var cleaningNotes: String = ""
        var mealPrepNotes: String = ""
        var updatedAt: Date = Date()
        init(weekStart: Date) { self.weekStart = weekStart }
    }

    @Model final class DayAssignment {
        var date: Date = Date.distantPast
        var kindRaw: String = DayKind.dayOff.rawValue
        var shiftStart: Int? = nil
        var shiftEnd: Int? = nil
        var breakStart: Int? = nil
        var breakMinutes: Int = 0
        var overtimeMinutes: Int = 0
        var leaveHome: Int? = nil
        var arrival: Int? = nil
        var returnHome: Int? = nil
        var isRecovery: Bool = false
        var note: String = ""
        var updatedAt: Date = Date()
        init(date: Date) { self.date = date }
    }

    // MARK: Tarefas
    @Model final class TaskItem {
        var uid: UUID = UUID()
        var title: String = ""
        var notes: String = ""
        var category: String = "personal"
        var priority: Int = 3
        var durationMinutes: Int = 10
        var timingData: Data = Data()
        var recurrenceData: Data = Data()
        var locationRaw: String = TaskLocation.home.rawValue
        var sharingRaw: String = "personal"
        var failureRaw: String = FailurePolicy.proposeReschedule.rawValue
        var deadline: Date? = nil
        var notify: Bool = false
        var notifyLeadMinutes: Int = 0
        var essential: Bool = false
        var heavy: Bool = false
        var preferDayOff: Bool = false
        var xpArea: String = "productivity"
        var parentUID: UUID? = nil
        var archived: Bool = false
        var createdAt: Date = Date()
        init(title: String) { self.title = title }
    }

    /// Registo esparso: só existe quando uma ocorrência muda de estado (feita, ignorada, falhada…).
    @Model final class TaskOccurrence {
        var taskUID: UUID = UUID()
        var date: Date = Date.distantPast
        var statusRaw: String = "pending"
        var completedAt: Date? = nil
        var snoozedUntil: Date? = nil
        var xpAwarded: Int = 0
        init(taskUID: UUID, date: Date, status: String) { self.taskUID = taskUID; self.date = date; self.statusRaw = status }
    }

    @Model final class DailyPriority {
        var date: Date = Date.distantPast
        var taskUIDs: [UUID] = []
        init(date: Date, taskUIDs: [UUID]) { self.date = date; self.taskUIDs = taskUIDs }
    }

    @Model final class RescheduleSuggestion {
        var taskUID: UUID = UUID()
        var title: String = ""
        var fromDate: Date = Date.distantPast
        var suggestedDate: Date = Date.distantPast
        var reason: String = ""
        var resolved: Bool = false
        init(taskUID: UUID, title: String, fromDate: Date, suggestedDate: Date, reason: String) {
            self.taskUID = taskUID; self.title = title; self.fromDate = fromDate; self.suggestedDate = suggestedDate; self.reason = reason
        }
    }

    // MARK: Nutrição, corpo, despensa
    @Model final class FoodItem {
        var name: String = ""
        var kcalPerUnit: Double = 0
        var proteinPerUnit: Double = 0
        var unit: String = "100 g"
        init(name: String, kcal: Double, protein: Double, unit: String) { self.name = name; kcalPerUnit = kcal; proteinPerUnit = protein; self.unit = unit }
    }

    @Model final class MealEntry {
        var date: Date = Date()
        var mealRaw: String = MealType.lunch.rawValue
        var name: String = ""
        var quantity: Double = 1
        var kcal: Double = 0
        var protein: Double = 0
        init(date: Date, meal: MealType, name: String, quantity: Double, kcal: Double, protein: Double) {
            self.date = date; mealRaw = meal.rawValue; self.name = name; self.quantity = quantity; self.kcal = kcal; self.protein = protein
        }
    }

    @Model final class WaterEntry {
        var date: Date = Date()
        var ml: Int = 0
        init(date: Date, ml: Int) { self.date = date; self.ml = ml }
    }

    @Model final class WeightEntry {
        var date: Date = Date()
        var kg: Double = 0
        init(date: Date, kg: Double) { self.date = date; self.kg = kg }
    }

    @Model final class BodyMeasurement {
        var date: Date = Date()
        var kind: String = ""
        var cm: Double = 0
        init(date: Date, kind: String, cm: Double) { self.date = date; self.kind = kind; self.cm = cm }
    }

    @Model final class ProgressPhoto {
        var date: Date = Date()
        var fileName: String = ""
        var note: String = ""
        init(date: Date, fileName: String) { self.date = date; self.fileName = fileName }
    }

    @Model final class PantryItem {
        var name: String = ""
        var quantity: Double = 1
        var unit: String = "un"
        var expiry: Date? = nil
        init(name: String, quantity: Double, unit: String) { self.name = name; self.quantity = quantity; self.unit = unit }
    }

    @Model final class ShoppingItem {
        var name: String = ""
        var quantity: String = ""
        var bought: Bool = false
        var createdAt: Date = Date()
        init(name: String, quantity: String) { self.name = name; self.quantity = quantity }
    }

    @Model final class Recipe {
        var name: String = ""
        var ingredientsData: Data = Data()
        var kcal: Double = 0
        var protein: Double = 0
        init(name: String) { self.name = name }
    }

    @Model final class PersonalProduct {
        var name: String = ""
        var have: Bool = true
        init(name: String) { self.name = name }
    }

    // MARK: Treino
    @Model final class Exercise {
        var name: String = ""
        var muscles: [String] = []
        var equipment: String = ""
        init(name: String, muscles: [String], equipment: String) { self.name = name; self.muscles = muscles; self.equipment = equipment }
    }

    @Model final class WorkoutTemplate {
        var name: String = ""
        var itemsData: Data = Data()
        var short: Bool = false
        init(name: String) { self.name = name }
    }

    @Model final class WorkoutSession {
        var date: Date = Date()
        var templateName: String = ""
        var durationMinutes: Int = 0
        var notes: String = ""
        var setsData: Data = Data()
        init(date: Date, templateName: String) { self.date = date; self.templateName = templateName }
    }

    // MARK: Finanças
    @Model final class Account {
        var name: String = ""
        var openingBalance: Decimal = 0
        var createdAt: Date = Date()
        init(name: String, openingBalance: Decimal) { self.name = name; self.openingBalance = openingBalance }
    }

    @Model final class IncomeEntry {
        var amount: Decimal = 0
        var date: Date = Date()
        var kindRaw: String = "salary"
        var note: String = ""
        var accountName: String = ""
        var importHash: String = ""
        init(amount: Decimal, date: Date, kind: String, note: String) { self.amount = amount; self.date = date; kindRaw = kind; self.note = note }
    }

    @Model final class Expense {
        var amount: Decimal = 0
        var date: Date = Date()
        var category: String = ""
        var desc: String = ""
        var paymentType: String = "Cartão"
        var isFixed: Bool = false
        var accountName: String = ""
        var importHash: String = ""
        init(amount: Decimal, date: Date, category: String, desc: String) { self.amount = amount; self.date = date; self.category = category; self.desc = desc }
    }

    @Model final class ExpenseCategory {
        var name: String = ""
        var icon: String = "tag"
        init(name: String, icon: String) { self.name = name; self.icon = icon }
    }

    @Model final class FixedExpense {
        var name: String = ""
        var amount: Decimal = 0
        var isEstimate: Bool = false
        var dayOfMonth: Int = 1
        var active: Bool = true
        var category: String = "Casa"
        init(name: String, amount: Decimal, isEstimate: Bool, dayOfMonth: Int, category: String) {
            self.name = name; self.amount = amount; self.isEstimate = isEstimate; self.dayOfMonth = dayOfMonth; self.category = category
        }
    }

    @Model final class Budget {
        var category: String = ""
        var monthlyLimit: Decimal = 0
        init(category: String, monthlyLimit: Decimal) { self.category = category; self.monthlyLimit = monthlyLimit }
    }

    @Model final class Debt {
        var uid: UUID = UUID()
        var creditor: String = ""
        var initialAmount: Decimal = 0
        var date: Date = Date()
        var dueDate: Date? = nil
        var settled: Bool = false
        init(creditor: String, initialAmount: Decimal) { self.creditor = creditor; self.initialAmount = initialAmount }
    }

    @Model final class DebtPayment {
        var debtUID: UUID = UUID()
        var amount: Decimal = 0
        var date: Date = Date()
        init(debtUID: UUID, amount: Decimal, date: Date) { self.debtUID = debtUID; self.amount = amount; self.date = date }
    }

    @Model final class SavingsGoal {
        var uid: UUID = UUID()
        var name: String = ""
        var target: Decimal = 0
        var deadline: Date? = nil
        var milestonesAwarded: Int = 0
        init(name: String, target: Decimal) { self.name = name; self.target = target }
    }

    @Model final class SavingsContribution {
        var goalUID: UUID = UUID()
        var amount: Decimal = 0
        var date: Date = Date()
        init(goalUID: UUID, amount: Decimal, date: Date) { self.goalUID = goalUID; self.amount = amount; self.date = date }
    }

    @Model final class MonthlyReport {
        var monthKey: String = ""
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fixed: Decimal = 0
        var saved: Decimal = 0
        var topCategory: String = ""
        var createdAt: Date = Date()
        init(monthKey: String) { self.monthKey = monthKey }
    }

    // MARK: Progressão
    @Model final class XPEvent {
        var date: Date = Date()
        var area: String = "productivity"
        var amount: Int = 0
        var source: String = ""
        var sourceKey: String = ""
        init(date: Date, area: String, amount: Int, source: String, sourceKey: String) {
            self.date = date; self.area = area; self.amount = amount; self.source = source; self.sourceKey = sourceKey
        }
    }

    @Model final class Goal {
        var uid: UUID = UUID()
        var area: String = "personal"
        var horizonRaw: String = "medium"
        var title: String = ""
        var metric: String = ""
        var startValue: Double = 0
        var targetValue: Double = 0
        var currentValue: Double = 0
        var deadline: Date? = nil
        var completed: Bool = false
        var autoSource: String = ""
        var createdAt: Date = Date()
        init(title: String, area: String) { self.title = title; self.area = area }
    }

    @Model final class AchievementUnlock {
        var key: String = ""
        var date: Date = Date()
        init(key: String) { self.key = key }
    }

    // MARK: Calendário e viagens
    @Model final class CalendarEvent {
        var title: String = ""
        var start: Date = Date()
        var end: Date = Date()
        var allDay: Bool = false
        var location: String = ""
        init(title: String, start: Date, end: Date) { self.title = title; self.start = start; self.end = end }
    }

    @Model final class Trip {
        var uid: UUID = UUID()
        var destination: String = ""
        var departure: Date = Date()
        var returnDate: Date = Date()
        var lodging: String = ""
        var transportToAirport: String = ""
        var minutesToAirport: Int = 60
        var remindersData: Data = Data()
        init(destination: String, departure: Date, returnDate: Date) { self.destination = destination; self.departure = departure; self.returnDate = returnDate }
    }

    @Model final class Flight {
        var tripUID: UUID = UUID()
        var number: String = ""
        var fromAirport: String = ""
        var toAirport: String = ""
        var departure: Date = Date()
        var arrival: Date = Date()
        var departureTZ: String = TimeZone.current.identifier
        var arrivalTZ: String = TimeZone.current.identifier
        init(tripUID: UUID) { self.tripUID = tripUID }
    }

    @Model final class ChecklistTemplate {
        var name: String = ""
        var itemsData: Data = Data()
        init(name: String) { self.name = name }
    }

    @Model final class TripChecklistItem {
        var tripUID: UUID = UUID()
        var category: String = ""
        var text: String = ""
        var checked: Bool = false
        init(tripUID: UUID, category: String, text: String) { self.tripUID = tripUID; self.category = category; self.text = text }
    }

    // MARK: Tempo livre e diversos
    @Model final class TimeLog {
        var date: Date = Date()
        var kindRaw: String = "free"
        var minutes: Int = 0
        var activity: String = ""
        init(date: Date, kind: String, minutes: Int, activity: String) { self.date = date; kindRaw = kind; self.minutes = minutes; self.activity = activity }
    }

    /// Pares chave/valor para definições e marcadores internos (sementes, último rollover, etc.).
    @Model final class AppMeta {
        var key: String = ""
        var value: String = ""
        init(key: String, value: String) { self.key = key; self.value = value }
    }
}

typealias WeekPlan = SchemaV2.WeekPlan
typealias DayAssignment = SchemaV2.DayAssignment
typealias TaskItem = SchemaV2.TaskItem
typealias TaskOccurrence = SchemaV2.TaskOccurrence
typealias DailyPriority = SchemaV2.DailyPriority
typealias RescheduleSuggestion = SchemaV2.RescheduleSuggestion
typealias FoodItem = SchemaV2.FoodItem
typealias MealEntry = SchemaV2.MealEntry
typealias WaterEntry = SchemaV2.WaterEntry
typealias WeightEntry = SchemaV2.WeightEntry
typealias BodyMeasurement = SchemaV2.BodyMeasurement
typealias ProgressPhoto = SchemaV2.ProgressPhoto
typealias PantryItem = SchemaV2.PantryItem
typealias ShoppingItem = SchemaV2.ShoppingItem
typealias Recipe = SchemaV2.Recipe
typealias PersonalProduct = SchemaV2.PersonalProduct
typealias Exercise = SchemaV2.Exercise
typealias WorkoutTemplate = SchemaV2.WorkoutTemplate
typealias WorkoutSession = SchemaV2.WorkoutSession
typealias Account = SchemaV2.Account
typealias IncomeEntry = SchemaV2.IncomeEntry
typealias Expense = SchemaV2.Expense
typealias ExpenseCategory = SchemaV2.ExpenseCategory
typealias FixedExpense = SchemaV2.FixedExpense
typealias Budget = SchemaV2.Budget
typealias Debt = SchemaV2.Debt
typealias DebtPayment = SchemaV2.DebtPayment
typealias SavingsGoal = SchemaV2.SavingsGoal
typealias SavingsContribution = SchemaV2.SavingsContribution
typealias MonthlyReport = SchemaV2.MonthlyReport
typealias XPEvent = SchemaV2.XPEvent
typealias Goal = SchemaV2.Goal
typealias AchievementUnlock = SchemaV2.AchievementUnlock
typealias CalendarEvent = SchemaV2.CalendarEvent
typealias Trip = SchemaV2.Trip
typealias Flight = SchemaV2.Flight
typealias ChecklistTemplate = SchemaV2.ChecklistTemplate
typealias TripChecklistItem = SchemaV2.TripChecklistItem
typealias TimeLog = SchemaV2.TimeLog
typealias AppMeta = SchemaV2.AppMeta

// MARK: - Codificação de campos compostos

enum Coding {
    static func encode<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }
    static func decode<T: Decodable>(_ t: T.Type, _ d: Data) -> T? { d.isEmpty ? nil : try? JSONDecoder().decode(t, from: d) }
}

enum OccurrenceStatus: String, CaseIterable {
    case pending, done, skippedToday, failed, rescheduled, waiting
    var title: String {
        switch self {
        case .pending: return "Pendente"
        case .done: return "Concluída"
        case .skippedToday: return "Ignorada hoje"
        case .failed: return "Falhada"
        case .rescheduled: return "Reagendada"
        case .waiting: return "À espera de outra pessoa"
        }
    }
}

enum Sharing: String, CaseIterable {
    case personal, shared
    var title: String { self == .personal ? "Pessoal" : "Partilhada" }
}

extension SchemaV2.TaskItem {
    var timing: TaskTiming {
        get { Coding.decode(TaskTiming.self, timingData) ?? .flexible(earliest: TimeOfDay(8), latest: TimeOfDay(22)) }
        set { timingData = Coding.encode(newValue) }
    }
    var recurrence: Recurrence {
        get { Coding.decode(Recurrence.self, recurrenceData) ?? .daily }
        set { recurrenceData = Coding.encode(newValue) }
    }
    var location: TaskLocation { TaskLocation(rawValue: locationRaw) ?? .home }
    var failurePolicy: FailurePolicy { FailurePolicy(rawValue: failureRaw) ?? .proposeReschedule }
    var sharing: Sharing { Sharing(rawValue: sharingRaw) ?? .personal }
}

extension SchemaV2.DayAssignment {
    var kind: DayKind {
        get { DayKind(rawValue: kindRaw) ?? .dayOff }
        set { kindRaw = newValue.rawValue }
    }

    var info: DayInfo {
        var shift: TimeRange?
        if let s = shiftStart, let e = shiftEnd, e >= s { shift = TimeRange(TimeOfDay(minutes: s), TimeOfDay(minutes: e)) }
        return DayInfo(date: date, kind: kind, shift: shift, breakStart: breakStart.map { TimeOfDay(minutes: $0) },
                       breakMinutes: breakMinutes, overtimeMinutes: overtimeMinutes,
                       leaveHome: leaveHome.map { TimeOfDay(minutes: $0) }, arrival: arrival.map { TimeOfDay(minutes: $0) },
                       returnHome: returnHome.map { TimeOfDay(minutes: $0) }, isRecovery: isRecovery)
    }

    func apply(_ d: DayInfo) {
        kind = d.kind
        shiftStart = d.shift?.start.minutes; shiftEnd = d.shift?.end.minutes
        breakStart = d.breakStart?.minutes; breakMinutes = d.breakMinutes; overtimeMinutes = d.overtimeMinutes
        leaveHome = d.leaveHome?.minutes; arrival = d.arrival?.minutes; returnHome = d.returnHome?.minutes
        isRecovery = d.isRecovery; updatedAt = Date()
    }
}
