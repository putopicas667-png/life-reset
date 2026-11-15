import Foundation
import SwiftData
import LifeResetCore

/// Plano de migrações. Ao criar o SchemaV2, acrescenta-se aqui `SchemaV2.self` e a respetiva etapa.
enum LifeResetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [v1ToV2] }
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
}

enum Persistence {
    /// Ficheiro da base de dados, no contentor privado da app (Application Support).
    /// Proteção de dados do iOS: "completa até ao primeiro desbloqueio", para que as ações das notificações
    /// possam gravar com o iPhone bloqueado (ver ARCHITECTURE §11).
    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "LifeReset.store")
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: storeURL)
        }
        let container = try ModelContainer(for: schema, migrationPlan: LifeResetMigrationPlan.self, configurations: [config])
        if !inMemory { protectStoreFiles() }
        return container
    }

    private static func protectStoreFiles() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path() + suffix
            if fm.fileExists(atPath: path) {
                try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            }
        }
    }
}

/// Acesso ao perfil e aos trabalhos (um único perfil por dispositivo).
@MainActor
struct ProfileRepository {
    let context: ModelContext

    func profile() -> UserProfile? {
        (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    func jobs() -> [Job] {
        (try? context.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    /// Grava o perfil e os trabalhos (cria-os se ainda não existirem).
    func save(profile settings: ProfileSettings, jobs jobSettings: [JobSettings]) throws {
        if let p = profile() {
            p.apply(settings)
            p.onboardingCompleted = true
        } else {
            context.insert(UserProfile(settings: settings, onboardingCompleted: true))
        }
        let existing = jobs()
        for (i, js) in jobSettings.enumerated() {
            if i < existing.count { existing[i].apply(js); existing[i].sortOrder = i }
            else { context.insert(Job(settings: js, sortOrder: i)) }
        }
        if existing.count > jobSettings.count {
            for j in existing[jobSettings.count...] { context.delete(j) }
        }
        try context.save()
    }
}
