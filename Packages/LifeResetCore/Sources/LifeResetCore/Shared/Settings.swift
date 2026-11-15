import Foundation

/// Definições pessoais (valores de referência). Tudo editável na app.
public struct ProfileSettings: Codable, Equatable, Sendable {
    public var wake: TimeOfDay
    public var bed: TimeOfDay
    public var startWeightKg: Double
    public var targetWeightKg: Double
    public var dailyKcal: Int
    public var dailyProteinG: Int
    public var dailyWaterMl: Int
    public var mainMeals: Int
    public var workoutsPerWeek: Int
    public var daysOffPerWeek: Int
    public var maxRecoveryDays: Int
    public var currencyCode: String
    public var foodPreferences: [String]

    public init(wake: TimeOfDay, bed: TimeOfDay, startWeightKg: Double, targetWeightKg: Double, dailyKcal: Int,
                dailyProteinG: Int, dailyWaterMl: Int, mainMeals: Int, workoutsPerWeek: Int, daysOffPerWeek: Int,
                maxRecoveryDays: Int, currencyCode: String, foodPreferences: [String]) {
        self.wake = wake; self.bed = bed
        self.startWeightKg = startWeightKg; self.targetWeightKg = targetWeightKg
        self.dailyKcal = dailyKcal; self.dailyProteinG = dailyProteinG; self.dailyWaterMl = dailyWaterMl
        self.mainMeals = mainMeals; self.workoutsPerWeek = workoutsPerWeek
        self.daysOffPerWeek = daysOffPerWeek; self.maxRecoveryDays = maxRecoveryDays
        self.currencyCode = currencyCode; self.foodPreferences = foodPreferences
    }

    /// Configuração inicial conhecida (especificação §25).
    public static let initial = ProfileSettings(
        wake: TimeOfDay(7, 30), bed: TimeOfDay(24, 0),
        startWeightKg: 50, targetWeightKg: 65,
        dailyKcal: 2800, dailyProteinG: 120, dailyWaterMl: 3000,
        mainMeals: 3, workoutsPerWeek: 4, daysOffPerWeek: 2, maxRecoveryDays: 2,
        currencyCode: "CHF",
        foodPreferences: ["Massa", "Arroz", "Ovos", "Frango", "Cogumelos", "Leite", "Bananas", "Atum", "Queijo", "Pão", "Carne de vaca", "Fruta"]
    )

    /// Problemas de coerência (vazio = válido).
    public func validationIssues() -> [String] {
        var out: [String] = []
        if targetWeightKg <= 0 || startWeightKg <= 0 { out.append("O peso tem de ser maior do que zero.") }
        if dailyKcal < 1000 || dailyKcal > 6000 { out.append("As calorias diárias devem estar entre 1000 e 6000 kcal.") }
        if dailyWaterMl < 500 || dailyWaterMl > 8000 { out.append("A água diária deve estar entre 0,5 e 8 L.") }
        if !(1...6).contains(mainMeals) { out.append("O número de refeições principais deve estar entre 1 e 6.") }
        if !(0...7).contains(workoutsPerWeek) { out.append("Os treinos por semana devem estar entre 0 e 7.") }
        if !(0...2).contains(maxRecoveryDays) { out.append("O Recovery Mode tem um máximo de 2 dias por semana.") }
        if wake.minutes >= 24 * 60 { out.append("A hora de despertar tem de ser antes da meia-noite.") }
        return out
    }
}

public enum JobKind: String, Codable, CaseIterable, Sendable {
    case burger, cafe, other
}

/// Configuração de um trabalho. Os turnos concretos de cada semana são definidos no Sunday Reset (Fase 2);
/// estes são os valores por omissão de cada turno.
public struct JobSettings: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name + kind.rawValue }
    public var name: String
    public var kind: JobKind
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var leaveHome: TimeOfDay
    /// Hora a que chega ao local de trabalho (antes da entrada).
    public var arrival: TimeOfDay
    public var returnHome: TimeOfDay
    public var breakMinutes: Int
    public var shiftsPerWeek: Int
    /// Dia fixo da semana (1 = domingo … 7 = sábado, como no `Calendar`), ou nil se variar.
    public var fixedWeekday: Int?

    public init(name: String, kind: JobKind, start: TimeOfDay, end: TimeOfDay, leaveHome: TimeOfDay, arrival: TimeOfDay,
                returnHome: TimeOfDay, breakMinutes: Int, shiftsPerWeek: Int, fixedWeekday: Int?) {
        self.name = name; self.kind = kind; self.start = start; self.end = end
        self.leaveHome = leaveHome; self.arrival = arrival; self.returnHome = returnHome
        self.breakMinutes = breakMinutes; self.shiftsPerWeek = shiftsPerWeek; self.fixedWeekday = fixedWeekday
    }

    public static let burgerInitial = JobSettings(
        name: "Hambúrgueres", kind: .burger,
        start: TimeOfDay(10, 30), end: TimeOfDay(22, 30),
        leaveHome: TimeOfDay(9, 20), arrival: TimeOfDay(10, 0), returnHome: TimeOfDay(23, 0),
        breakMinutes: 60, shiftsPerWeek: 4, fixedWeekday: nil)

    public static let cafeInitial = JobSettings(
        name: "Café", kind: .cafe,
        start: TimeOfDay(14, 0), end: TimeOfDay(20, 30),
        leaveHome: TimeOfDay(12, 50), arrival: TimeOfDay(14, 0), returnHome: TimeOfDay(22, 0),
        breakMinutes: 30, shiftsPerWeek: 1, fixedWeekday: 1)

    public var shiftDuration: Int { start.minutes(until: end) }
    /// Minutos livres entre a chegada e a entrada (ex.: 30 min nos hambúrgueres).
    public var preShiftWindow: Int { max(0, arrival.minutes(until: start)) }
    /// Tempo de deslocação de ida.
    public var commuteToWork: Int { max(0, leaveHome.minutes(until: arrival)) }
    /// Tempo de deslocação de regresso.
    public var commuteHome: Int { max(0, end.minutes(until: returnHome)) }

    public func validationIssues() -> [String] {
        var out: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("O trabalho precisa de um nome.") }
        if end <= start { out.append("\(name): a saída tem de ser depois da entrada.") }
        if leaveHome > arrival { out.append("\(name): a saída de casa tem de ser antes da chegada.") }
        if arrival > start { out.append("\(name): a chegada tem de ser até à hora de entrada.") }
        if returnHome < end { out.append("\(name): o regresso a casa tem de ser depois da saída.") }
        if breakMinutes < 0 || breakMinutes >= max(1, shiftDuration) { out.append("\(name): a pausa tem de ser mais curta do que o turno.") }
        if !(0...7).contains(shiftsPerWeek) { out.append("\(name): os turnos por semana devem estar entre 0 e 7.") }
        if let d = fixedWeekday, !(1...7).contains(d) { out.append("\(name): dia da semana inválido.") }
        return out
    }
}
