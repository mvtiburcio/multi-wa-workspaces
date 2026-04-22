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

  public private(set) var maxWarmWebViews: Int?
  private var entries: [UUID: Entry] = [:]

  public init(maxWarmWebViews: Int? = nil) {
    setMaxWarmWebViews(maxWarmWebViews)
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
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    installDesktopNavigatorSpoof(on: config)

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.customUserAgent = UserAgentProfile.whatsAppDesktopSafari
    entries[workspace.id] = Entry(
      workspaceID: workspace.id,
      dataStoreID: workspace.dataStoreID,
      webView: webView,
      lastAccessedAt: Date()
    )

    evictIfNeeded(excluding: workspace.id)
    return webView
  }

  public var cachedCount: Int {
    entries.count
  }

  public func setMaxWarmWebViews(_ value: Int?) {
    if let value {
      maxWarmWebViews = max(1, value)
    } else {
      maxWarmWebViews = nil
    }
    evictIfNeeded(excluding: nil)
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

  private func evictIfNeeded(excluding workspaceID: UUID?) {
    guard let maxWarmWebViews else {
      return
    }

    while entries.count > maxWarmWebViews {
      let candidate = entries
        .values
        .filter { workspaceID == nil || $0.workspaceID != workspaceID }
        .min { $0.lastAccessedAt < $1.lastAccessedAt }

      guard let candidate else {
        break
      }
      release(workspaceID: candidate.workspaceID)
    }
  }

  private func installDesktopNavigatorSpoof(on configuration: WKWebViewConfiguration) {
    let script = """
      (() => {
        const define = (object, key, value) => {
          try {
            Object.defineProperty(object, key, {
              get: () => value,
              configurable: true
            });
          } catch (_) {}
        };

        define(Navigator.prototype, 'platform', 'MacIntel');
        define(Navigator.prototype, 'vendor', 'Apple Computer, Inc.');
        define(Navigator.prototype, 'userAgent', '\(UserAgentProfile.whatsAppDesktopSafari)');
        define(Navigator.prototype, 'appVersion', '\(UserAgentProfile.whatsAppDesktopSafari)');
        define(Navigator.prototype, 'maxTouchPoints', 0);

        const originalMatchMedia = window.matchMedia;
        window.matchMedia = (query) => {
          if (query && query.includes('pointer: coarse')) {
            return {
              matches: false,
              media: query,
              onchange: null,
              addListener() {},
              removeListener() {},
              addEventListener() {},
              removeEventListener() {},
              dispatchEvent() { return false; }
            };
          }
          return originalMatchMedia(query);
        };
      })();
    """

    let userScript = WKUserScript(
      source: script,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: false
    )
    configuration.userContentController.addUserScript(userScript)
  }
}
