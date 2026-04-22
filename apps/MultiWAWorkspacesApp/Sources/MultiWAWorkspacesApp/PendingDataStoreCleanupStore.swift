import Foundation
import OSLog

@MainActor
final class PendingDataStoreCleanupStore {
  private let userDefaults: UserDefaults
  private let key = "pending_datastore_cleanup_ids.v1"

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func all() -> [UUID] {
    storedStrings().compactMap(UUID.init(uuidString:))
  }

  func enqueue(_ identifier: UUID) {
    var ids = all()
    guard !ids.contains(identifier) else {
      return
    }
    ids.append(identifier)
    persist(ids)
  }

  func remove(_ identifier: UUID) {
    var ids = all()
    ids.removeAll { $0 == identifier }
    persist(ids)
  }

  private func storedStrings() -> [String] {
    userDefaults.array(forKey: key) as? [String] ?? []
  }

  private func persist(_ ids: [UUID]) {
    userDefaults.set(ids.map(\.uuidString), forKey: key)
  }
}

@MainActor
final class PendingDataStoreCleanupProcessor {
  private let logger: Logger
  private let queueStore: PendingDataStoreCleanupStore
  private let remover: @MainActor @Sendable (UUID) async throws -> Void
  private let isRecoverableError: @MainActor @Sendable (Error) -> Bool

  init(
    queueStore: PendingDataStoreCleanupStore,
    logger: Logger = Logger(subsystem: "com.multiwa.workspaces", category: "pending_datastore_cleanup"),
    remover: @escaping @MainActor @Sendable (UUID) async throws -> Void,
    isRecoverableError: @escaping @MainActor @Sendable (Error) -> Bool
  ) {
    self.queueStore = queueStore
    self.logger = logger
    self.remover = remover
    self.isRecoverableError = isRecoverableError
  }

  func processPending() async {
    let pending = queueStore.all()
    guard !pending.isEmpty else {
      return
    }

    for identifier in pending {
      do {
        try await remover(identifier)
        queueStore.remove(identifier)
        logger.info(
          "workspace_id=\(identifier.uuidString, privacy: .public) event=pending_datastore_cleanup duration_ms=0 result=removed"
        )
      } catch {
        if isRecoverableError(error) {
          logger.warning(
            "workspace_id=\(identifier.uuidString, privacy: .public) event=pending_datastore_cleanup duration_ms=0 result=recoverable_retry_later error=\(String(describing: error), privacy: .public)"
          )
          continue
        }

        queueStore.remove(identifier)
        logger.error(
          "workspace_id=\(identifier.uuidString, privacy: .public) event=pending_datastore_cleanup duration_ms=0 result=non_recoverable_dropped error=\(String(describing: error), privacy: .public)"
        )
      }
    }
  }
}
