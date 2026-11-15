import Foundation
import SwiftData
import LifeResetCore

/// Esquema de dados v1 (Fase 1): perfil e trabalhos.
/// Cada alteração futura ao modelo cria um SchemaV2, SchemaV3… com uma etapa em `LifeResetMigrationPlan`.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [UserProfile.self, Job.self] }

    @Model
    final class UserProfile {
        var createdAt: Date
        var updatedAt: Date
        var wakeMinutes: Int
        var bedMinutes: Int
        var startWeightKg: Double
        var targetWeightKg: Double
        var dailyKcal: Int
        var dailyProteinG: Int
        var dailyWaterMl: Int
        var mainMeals: Int
        var workoutsPerWeek: Int
        var daysOffPerWeek: Int
        var maxRecoveryDays: Int
        var currencyCode: String
        var foodPreferences: [String]
        var onboardingCompleted: Bool

        init(settings s: ProfileSettings, onboardingCompleted: Bool) {
            createdAt = .now; updatedAt = .now
            wakeMinutes = s.wake.minutes; bedMinutes = s.bed.minutes
            startWeightKg = s.startWeightKg; targetWeightKg = s.targetWeightKg
            dailyKcal = s.dailyKcal; dailyProteinG = s.dailyProteinG; dailyWaterMl = s.dailyWaterMl
            mainMeals = s.mainMeals; workoutsPerWeek = s.workoutsPerWeek
            daysOffPerWeek = s.daysOffPerWeek; maxRecoveryDays = s.maxRecoveryDays
            currencyCode = s.currencyCode; foodPreferences = s.foodPreferences
            self.onboardingCompleted = onboardingCompleted
        }
    }

    @Model
    final class Job {
        var createdAt: Date
        var updatedAt: Date
        var name: String
        var kindRaw: String
        var startMinutes: Int
        var endMinutes: Int
        var leaveHomeMinutes: Int
        var arrivalMinutes: Int
        var returnHomeMinutes: Int
        var breakMinutes: Int
        var shiftsPerWeek: Int
        var fixedWeekday: Int?
        var sortOrder: Int

        init(settings s: JobSettings, sortOrder: Int) {
            createdAt = .now; updatedAt = .now
            name = s.name; kindRaw = s.kind.rawValue
            startMinutes = s.start.minutes; endMinutes = s.end.minutes
            leaveHomeMinutes = s.leaveHome.minutes; arrivalMinutes = s.arrival.minutes
            returnHomeMinutes = s.returnHome.minutes; breakMinutes = s.breakMinutes
            shiftsPerWeek = s.shiftsPerWeek; fixedWeekday = s.fixedWeekday
            self.sortOrder = sortOrder
        }
    }
}

typealias UserProfile = SchemaV1.UserProfile
typealias Job = SchemaV1.Job

// MARK: - Conversão para os tipos do Core

extension SchemaV1.UserProfile {
    var settings: ProfileSettings {
        ProfileSettings(wake: TimeOfDay(minutes: wakeMinutes), bed: TimeOfDay(minutes: bedMinutes),
                        startWeightKg: startWeightKg, targetWeightKg: targetWeightKg, dailyKcal: dailyKcal,
                        dailyProteinG: dailyProteinG, dailyWaterMl: dailyWaterMl, mainMeals: mainMeals,
                        workoutsPerWeek: workoutsPerWeek, daysOffPerWeek: daysOffPerWeek,
                        maxRecoveryDays: maxRecoveryDays, currencyCode: currencyCode, foodPreferences: foodPreferences)
    }

    func apply(_ s: ProfileSettings) {
        wakeMinutes = s.wake.minutes; bedMinutes = s.bed.minutes
        startWeightKg = s.startWeightKg; targetWeightKg = s.targetWeightKg
        dailyKcal = s.dailyKcal; dailyProteinG = s.dailyProteinG; dailyWaterMl = s.dailyWaterMl
        mainMeals = s.mainMeals; workoutsPerWeek = s.workoutsPerWeek
        daysOffPerWeek = s.daysOffPerWeek; maxRecoveryDays = s.maxRecoveryDays
        currencyCode = s.currencyCode; foodPreferences = s.foodPreferences
        updatedAt = .now
    }
}

extension SchemaV1.Job {
    var settings: JobSettings {
        JobSettings(name: name, kind: JobKind(rawValue: kindRaw) ?? .other,
                    start: TimeOfDay(minutes: startMinutes), end: TimeOfDay(minutes: endMinutes),
                    leaveHome: TimeOfDay(minutes: leaveHomeMinutes), arrival: TimeOfDay(minutes: arrivalMinutes),
                    returnHome: TimeOfDay(minutes: returnHomeMinutes), breakMinutes: breakMinutes,
                    shiftsPerWeek: shiftsPerWeek, fixedWeekday: fixedWeekday)
    }

    func apply(_ s: JobSettings) {
        name = s.name; kindRaw = s.kind.rawValue
        startMinutes = s.start.minutes; endMinutes = s.end.minutes
        leaveHomeMinutes = s.leaveHome.minutes; arrivalMinutes = s.arrival.minutes
        returnHomeMinutes = s.returnHome.minutes; breakMinutes = s.breakMinutes
        shiftsPerWeek = s.shiftsPerWeek; fixedWeekday = s.fixedWeekday
        updatedAt = .now
    }
}
