import Foundation
import SwiftData

/// Depois de cada gravação: reagenda notificações e atualiza o snapshot dos widgets (agrupado, com atraso curto).
@MainActor
final class ChangeCoordinator {
    static let shared = ChangeCoordinator()
    private var pending: Task<Void, Never>?
    var hooks: [(ModelContext) -> Void] = []

    func didChange(_ ctx: ModelContext) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            for h in self.hooks { h(ctx) }
        }
    }
}
