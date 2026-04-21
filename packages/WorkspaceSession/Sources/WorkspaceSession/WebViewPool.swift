import Foundation
import WebKit
import WorkspaceDomain

@MainActor
public final class WebViewPool {
  private struct Entry {
    let workspaceID: UUID
    let dataStoreID: UUID
    let webView: WKWebView
    var lastAccessedAt: Date
  }

  public let maxWarmWebViews: Int
  private var entries: [UUID: Entry] = [:]

  public init(maxWarmWebViews: Int = 2) {
    self.maxWarmWebViews = max(1, maxWarmWebViews)
  }

  public var cachedWorkspaceIDs: [UUID] {
    entries.keys.sorted { lhs, rhs in
      guard
        let left = entries[lhs]?.lastAccessedAt,
        let right = entries[rhs]?.lastAccessedAt
      else {
        return lhs.uuidString < rhs.uuidString
      }
      return left > right
    }
  }

  public func webView(for workspace: Workspace) -> WKWebView {
    if let entry = entries[workspace.id] {
      if entry.dataStoreID == workspace.dataStoreID {
        touch(workspaceID: workspace.id)
        return entry.webView
      }

      entry.webView.stopLoading()
      entry.webView.navigationDelegate = nil
      entries.removeValue(forKey: workspace.id)
    }

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WebsiteDataStoreManager.dataStore(for: workspace.dataStoreID)

    let webView = WKWebView(frame: .zero, configuration: config)
    entries[workspace.id] = Entry(
      workspaceID: workspace.id,
      dataStoreID: workspace.dataStoreID,
      webView: webView,
      lastAccessedAt: Date()
    )

    evictIfNeeded(excluding: workspace.id)
    return webView
  }

  public func release(workspaceID: UUID) {
    guard let entry = entries.removeValue(forKey: workspaceID) else {
      return
    }
    entry.webView.stopLoading()
    entry.webView.navigationDelegate = nil
    entry.webView.removeFromSuperview()
  }

  private func touch(workspaceID: UUID) {
    guard var entry = entries[workspaceID] else {
      return
    }
    entry.lastAccessedAt = Date()
    entries[workspaceID] = entry
  }

  private func evictIfNeeded(excluding workspaceID: UUID) {
    while entries.count > maxWarmWebViews {
      let candidate = entries
        .values
        .filter { $0.workspaceID != workspaceID }
        .min { $0.lastAccessedAt < $1.lastAccessedAt }

      guard let candidate else {
        break
      }
      release(workspaceID: candidate.workspaceID)
    }
  }
}
