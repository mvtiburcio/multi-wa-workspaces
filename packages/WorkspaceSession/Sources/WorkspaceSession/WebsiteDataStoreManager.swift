import Foundation
import OSLog
import WebKit

@MainActor
public enum WebsiteDataStoreManager {
  private static let logger = Logger(subsystem: "com.multiwa.workspaces", category: "website_data_store")

  public static func dataStore(for identifier: UUID) -> WKWebsiteDataStore {
    WKWebsiteDataStore(forIdentifier: identifier)
  }

  public static func removeDataStore(for identifier: UUID) async throws {
    let maxAttempts = 8
    var attempt = 1
    var delay: Duration = .milliseconds(120)

    while true {
      do {
        try await removeDataStoreOnce(for: identifier)
        logger.info(
          "workspace_id=\(identifier.uuidString, privacy: .public) event=datastore_removed duration_ms=0 result=success attempt=\(attempt, privacy: .public)"
        )
        return
      } catch {
        let isInUse = isDataStoreInUseError(error)
        if isInUse && attempt < maxAttempts {
          logger.warning(
            "workspace_id=\(identifier.uuidString, privacy: .public) event=datastore_remove_retry duration_ms=0 result=\(String(describing: error), privacy: .public) attempt=\(attempt, privacy: .public)"
          )
          try? await Task.sleep(for: delay)
          attempt += 1
          delay = min(delay * 2, .seconds(1))
          continue
        }
        logger.error(
          "workspace_id=\(identifier.uuidString, privacy: .public) event=datastore_remove_failed duration_ms=0 result=\(String(describing: error), privacy: .public) attempt=\(attempt, privacy: .public)"
        )
        throw error
      }
    }
  }

  private static func removeDataStoreOnce(for identifier: UUID) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: ())
      }
    }
  }

  public static func isDataStoreInUseError(_ error: Error) -> Bool {
    let nsError = error as NSError
    let domain = nsError.domain.lowercased()
    let description = nsError.localizedDescription.lowercased()

    let domainMatches = domain.contains("wkwebsite") || domain.contains("wkwebsitedatastore")
    let messageMatches = description.contains("data store is in use") || description.contains("in use by network process")
    let codeMatches = nsError.code == -1
    return messageMatches || (domainMatches && codeMatches)
  }
}
