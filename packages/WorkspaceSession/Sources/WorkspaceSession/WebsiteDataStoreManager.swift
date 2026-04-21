import Foundation
import WebKit

@MainActor
public enum WebsiteDataStoreManager {
  public static func dataStore(for identifier: UUID) -> WKWebsiteDataStore {
    WKWebsiteDataStore(forIdentifier: identifier)
  }

  public static func removeDataStore(for identifier: UUID) async throws {
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
}
