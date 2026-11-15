import Foundation
import CryptoKit
import CommonCrypto
import Security
import SwiftData

/// Cópia de segurança cifrada (AES-GCM, chave derivada da palavra-passe com PBKDF2-SHA256).
/// Contém a base de dados e, opcionalmente, as fotos de progresso. Nada sai do iPhone sem o utilizador partilhar o ficheiro.
enum Backup {
    enum Failure: LocalizedError {
        case wrongFormat, wrongPassword, io(String)
        var errorDescription: String? {
            switch self {
            case .wrongFormat: return "Este ficheiro não é uma cópia do LIFE RESET."
            case .wrongPassword: return "Palavra-passe errada ou ficheiro danificado."
            case .io(let s): return s
            }
        }
    }

    static let magic = Data("LRB1".utf8)
    static let iterations: UInt32 = 200_000
    static var pendingRestoreDir: URL { URL.applicationSupportDirectory.appending(path: "RestorePending", directoryHint: .isDirectory) }
    static var photosDir: URL { URL.applicationSupportDirectory.appending(path: "Photos", directoryHint: .isDirectory) }

    static func deriveKey(_ password: String, salt: Data) -> SymmetricKey {
        var key = Data(count: 32)
        let pw = Array(password.utf8)
        key.withUnsafeMutableBytes { k in
            salt.withUnsafeBytes { s in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                         s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                         k.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return SymmetricKey(data: key)
    }

    // Arquivo simples: [nome UTF-8 (UInt16 tamanho)][dados (UInt64 tamanho)]…
    static func pack(_ files: [(String, Data)]) -> Data {
        var out = Data()
        for (name, data) in files {
            let n = Data(name.utf8)
            var nl = UInt16(n.count).bigEndian, dl = UInt64(data.count).bigEndian
            out.append(Data(bytes: &nl, count: 2)); out.append(n)
            out.append(Data(bytes: &dl, count: 8)); out.append(data)
        }
        return out
    }

    static func unpack(_ d: Data) throws -> [(String, Data)] {
        var out: [(String, Data)] = []
        var i = d.startIndex
        func read(_ n: Int) throws -> Data {
            guard d.distance(from: i, to: d.endIndex) >= n else { throw Failure.wrongFormat }
            let r = d[i..<d.index(i, offsetBy: n)]; i = d.index(i, offsetBy: n); return Data(r)
        }
        while i < d.endIndex {
            let nl = try read(2).reduce(0) { ($0 << 8) | Int($1) }
            guard let name = String(data: try read(nl), encoding: .utf8) else { throw Failure.wrongFormat }
            let dl = try read(8).reduce(0) { ($0 << 8) | Int($1) }
            out.append((name, try read(dl)))
        }
        return out
    }

    /// Cria o ficheiro cifrado num local temporário (para partilhar/guardar em Ficheiros).
    @MainActor
    static func export(password: String, includePhotos: Bool, context: ModelContext) throws -> URL {
        try? context.save()
        let fm = FileManager.default
        var files: [(String, Data)] = []
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: Persistence.storeURL.path(percentEncoded: false) + suffix)
            if let d = try? Data(contentsOf: url) { files.append(("db/LifeReset.store" + suffix, d)) }
        }
        guard !files.isEmpty else { throw Failure.io("Não encontrei a base de dados.") }
        if includePhotos, let names = try? fm.contentsOfDirectory(atPath: photosDir.path(percentEncoded: false)) {
            for n in names { if let d = try? Data(contentsOf: photosDir.appending(path: n)) { files.append(("photos/" + n, d)) } }
        }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let sealed = try AES.GCM.seal(pack(files), using: deriveKey(password, salt: salt))
        guard let combined = sealed.combined else { throw Failure.io("Falha a cifrar.") }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = fm.temporaryDirectory.appending(path: "LifeReset-\(f.string(from: Date())).lrbackup")
        try (magic + salt + combined).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Decifra e prepara o restauro; os ficheiros só substituem a base de dados no próximo arranque.
    static func prepareRestore(from url: URL, password: String) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw Failure.io("Não foi possível ler o ficheiro.") }
        guard data.count > 4 + 16 + 28, data.prefix(4) == magic else { throw Failure.wrongFormat }
        let salt = data.subdata(in: 4..<20)
        let payload: Data
        do {
            payload = try AES.GCM.open(AES.GCM.SealedBox(combined: data.subdata(in: 20..<data.count)), using: deriveKey(password, salt: salt))
        } catch { throw Failure.wrongPassword }
        let files = try unpack(payload)
        guard files.contains(where: { $0.0 == "db/LifeReset.store" }) else { throw Failure.wrongFormat }
        let fm = FileManager.default
        try? fm.removeItem(at: pendingRestoreDir)
        try fm.createDirectory(at: pendingRestoreDir, withIntermediateDirectories: true)
        for (name, d) in files {
            let target = pendingRestoreDir.appending(path: name)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try d.write(to: target, options: [.atomic, .completeFileProtection])
        }
        return files.count
    }

    /// Chamado antes de abrir a base de dados: aplica um restauro pendente.
    static func applyPendingRestoreIfNeeded() {
        let fm = FileManager.default
        let db = pendingRestoreDir.appending(path: "db")
        guard fm.fileExists(atPath: db.appending(path: "LifeReset.store").path(percentEncoded: false)) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let dst = URL(fileURLWithPath: Persistence.storeURL.path(percentEncoded: false) + suffix)
            try? fm.removeItem(at: dst)
            let src = db.appending(path: "LifeReset.store" + suffix)
            if fm.fileExists(atPath: src.path(percentEncoded: false)) { try? fm.moveItem(at: src, to: dst) }
        }
        let photos = pendingRestoreDir.appending(path: "photos")
        if let names = try? fm.contentsOfDirectory(atPath: photos.path(percentEncoded: false)) {
            try? fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
            for n in names {
                let dst = photosDir.appending(path: n)
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: photos.appending(path: n), to: dst)
            }
        }
        try? fm.removeItem(at: pendingRestoreDir)
    }
}
