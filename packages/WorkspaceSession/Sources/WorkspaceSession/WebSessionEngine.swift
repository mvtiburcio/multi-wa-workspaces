import Foundation
import OSLog
import WebKit
import WorkspaceDomain

@MainActor
public protocol WebSessionStateReporting: AnyObject {
  var onStateChange: (@MainActor (UUID, WorkspaceState) -> Void)? { get set }
}

@MainActor
public protocol WebSessionUnreadReporting: AnyObject {
  var onUnreadCountChange: (@MainActor (UUID, Int, Int) -> Void)? { get set }
}

@MainActor
public final class WebSessionEngine: NSObject, WebSessionControlling, WebSessionStateReporting, WebSessionUnreadReporting, WebSessionDiagnosticsReporting, WebSessionWarmPoolControlling {
  public var onStateChange: (@MainActor (UUID, WorkspaceState) -> Void)?
  public var onUnreadCountChange: (@MainActor (UUID, Int, Int) -> Void)?

  private let pool: WebViewPool
  private let logger: Logger
  private let baseURL = URL(string: "https://web.whatsapp.com")!
  private var webViewWorkspaceMap: [ObjectIdentifier: UUID] = [:]
  private var titleObservers: [ObjectIdentifier: NSKeyValueObservation] = [:]
  private var unreadByWorkspace: [UUID: Int] = [:]
  private var lastKnownState: [UUID: WorkspaceState] = [:]
  private var loadingRecoveryTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
  private var disconnectedRecoveryTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

  public init(
    pool: WebViewPool = WebViewPool(),
    logger: Logger = Logger(subsystem: "com.waspaces.app", category: "web_session_engine")
  ) {
    self.pool = pool
    self.logger = logger
  }

  public func webView(for workspace: Workspace) async throws -> WKWebView {
    let startedAt = ContinuousClock.now

    let webView = pool.webView(for: workspace)
    webView.navigationDelegate = self
    webViewWorkspaceMap[ObjectIdentifier(webView)] = workspace.id
    ensureTitleObserver(for: webView, workspaceID: workspace.id)

    if webView.url == nil {
      loadRootURL(in: webView, workspaceID: workspace.id, reason: "initial_load")
    } else if webView.isLoading {
      lastKnownState[workspace.id] = .loading
      onStateChange?(workspace.id, .loading)
      scheduleLoadingRecovery(for: webView, workspaceID: workspace.id)
    } else {
      let cachedState = lastKnownState[workspace.id] ?? .connected
      onStateChange?(workspace.id, cachedState)
      Task { @MainActor [weak self, weak webView] in
        guard
          let self,
          let webView,
          self.webViewWorkspaceMap[ObjectIdentifier(webView)] == workspace.id
        else {
          return
        }
        let state = await self.detectState(for: webView, workspaceID: workspace.id)
        self.lastKnownState[workspace.id] = state
        self.onStateChange?(workspace.id, state)
        self.refreshUnreadCount(for: webView, workspaceID: workspace.id)
      }
    }

    let webViewPointer = pointerString(for: webView)
    let dataStorePointer = pointerString(for: webView.configuration.websiteDataStore)

    log(
      event: "webview_ready",
      workspaceID: workspace.id,
      result: "success webview=\(webViewPointer) datastore=\(dataStorePointer) datastore_id=\(workspace.dataStoreID.uuidString)",
      startedAt: startedAt
    )

    return webView
  }

  public func destroySession(for workspaceID: UUID) async throws {
    let startedAt = ContinuousClock.now

    let keysToRemove = webViewWorkspaceMap.compactMap { key, mappedWorkspaceID in
      mappedWorkspaceID == workspaceID ? key : nil
    }
    for key in keysToRemove {
      titleObservers[key]?.invalidate()
      titleObservers.removeValue(forKey: key)
      webViewWorkspaceMap.removeValue(forKey: key)
      loadingRecoveryTasks[key]?.cancel()
      loadingRecoveryTasks.removeValue(forKey: key)
      disconnectedRecoveryTasks[key]?.cancel()
      disconnectedRecoveryTasks.removeValue(forKey: key)
    }

    pool.release(workspaceID: workspaceID)
    unreadByWorkspace.removeValue(forKey: workspaceID)
    lastKnownState.removeValue(forKey: workspaceID)
    onStateChange?(workspaceID, .cold)

    log(
      event: "session_destroyed",
      workspaceID: workspaceID,
      result: "success",
      startedAt: startedAt
    )
  }

  public func diagnostics() -> WebSessionDiagnostics {
    WebSessionDiagnostics(
      cachedWebViewCount: pool.cachedCount,
      trackedWebViewCount: webViewWorkspaceMap.count,
      trackedWorkspaceCount: Set(webViewWorkspaceMap.values).count
    )
  }

  public func setWarmWebViewLimit(_ limit: Int?) {
    pool.setMaxWarmWebViews(limit)
  }

  private func log(
    event: String,
    workspaceID: UUID,
    result: String,
    startedAt: ContinuousClock.Instant
  ) {
    let duration = startedAt.duration(to: ContinuousClock.now)
    let durationMS = Int((Double(duration.components.seconds) * 1_000) + (Double(duration.components.attoseconds) / 1_000_000_000_000_000))

    logger.info(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=\(event, privacy: .public) duration_ms=\(durationMS, privacy: .public) result=\(result, privacy: .public)"
    )
  }
}

extension WebSessionEngine: WKNavigationDelegate {
  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    guard let workspaceID = webViewWorkspaceMap[ObjectIdentifier(webView)] else {
      return
    }
    lastKnownState[workspaceID] = .loading
    onStateChange?(workspaceID, .loading)
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let workspaceID = webViewWorkspaceMap[ObjectIdentifier(webView)] else {
      return
    }

    Task { @MainActor in
      let state = await detectState(for: webView, workspaceID: workspaceID)
      lastKnownState[workspaceID] = state
      onStateChange?(workspaceID, state)
      refreshUnreadCount(for: webView, workspaceID: workspaceID)
      logger.info(
        "workspace_id=\(workspaceID.uuidString, privacy: .public) event=navigation_finished duration_ms=0 result=\(state.rawValue, privacy: .public)"
      )
    }
  }

  public func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: any Error
  ) {
    guard let workspaceID = webViewWorkspaceMap[ObjectIdentifier(webView)] else {
      return
    }

    if isCancelledNavigationError(error) {
      logger.info(
        "workspace_id=\(workspaceID.uuidString, privacy: .public) event=navigation_cancelled duration_ms=0 result=ignored"
      )
      return
    }

    if isTransientNetworkError(error) {
      lastKnownState[workspaceID] = .disconnected
      onStateChange?(workspaceID, .disconnected)
      logger.warning(
        "workspace_id=\(workspaceID.uuidString, privacy: .public) event=navigation_disconnected duration_ms=0 result=\(String(describing: error), privacy: .public)"
      )
      scheduleDisconnectedRecovery(for: webView, workspaceID: workspaceID)
      return
    }

    lastKnownState[workspaceID] = .failed
    onStateChange?(workspaceID, .failed)
    logger.error(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=navigation_failed duration_ms=0 result=\(String(describing: error), privacy: .public)"
    )
  }

  public func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    self.webView(webView, didFail: navigation, withError: error)
  }

  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard let workspaceID = webViewWorkspaceMap[ObjectIdentifier(webView)] else {
      return
    }

    logger.error(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=webcontent_terminated duration_ms=0 result=reloading"
    )
    lastKnownState[workspaceID] = .loading
    loadRootURL(in: webView, workspaceID: workspaceID, reason: "webcontent_terminated")
  }

  private func detectState(for webView: WKWebView, workspaceID: UUID) async -> WorkspaceState {
    let script = """
      (() => {
        const expectedWorkspaceID = '\(workspaceID.uuidString)';
        const markerKey = '__waspaces_workspace_id';

        const readyState = document.readyState || 'unknown';
        const hasQR = !!document.querySelector('[data-testid="qrcode"]')
          || !!document.querySelector('canvas[aria-label*="Scan"]')
          || !!document.querySelector('canvas[aria-label*="Escaneie"]');
        const hasChatList = !!document.querySelector('[data-testid="chat-list"]')
          || !!document.querySelector('#pane-side');
        const bodyText = (document.body?.innerText || '').toLowerCase();
        const unsupportedBrowser =
          bodyText.includes('works on safari 15') ||
          bodyText.includes('funciona no safari 15');

        let existingMarker = null;
        let crossWorkspaceLeak = false;
        try {
          existingMarker = localStorage.getItem(markerKey);
          if (!existingMarker) {
            localStorage.setItem(markerKey, expectedWorkspaceID);
            existingMarker = expectedWorkspaceID;
          } else if (existingMarker !== expectedWorkspaceID) {
            crossWorkspaceLeak = true;
          }
        } catch (_) {
          // localStorage may be blocked on some intermediate pages.
        }

        return JSON.stringify({
          hasQR,
          hasChatList,
          unsupportedBrowser,
          readyState,
          existingMarker,
          crossWorkspaceLeak
        });
      })();
    """

    do {
      let payload = try await webView.evaluateJavaScript(script)
      guard
        let json = payload as? String,
        let data = json.data(using: .utf8),
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return .connected
      }

      let hasQR = decoded["hasQR"] as? Bool ?? false
      let hasChatList = decoded["hasChatList"] as? Bool ?? false
      let unsupportedBrowser = decoded["unsupportedBrowser"] as? Bool ?? false
      let readyState = (decoded["readyState"] as? String ?? "unknown").lowercased()
      let existingMarker = decoded["existingMarker"] as? String
      let crossWorkspaceLeak = decoded["crossWorkspaceLeak"] as? Bool ?? false

      if crossWorkspaceLeak {
        logger.error(
          "workspace_id=\(workspaceID.uuidString, privacy: .public) event=workspace_leak_detected duration_ms=0 result=marker=\(existingMarker ?? "nil", privacy: .public)"
        )
        return .failed
      }

      if unsupportedBrowser {
        return .failed
      }

      if hasQR {
        return .qrRequired
      }
      if hasChatList {
        return .connected
      }
      if readyState == "loading" {
        return .loading
      }
      return .connected
    } catch {
      return .connected
    }
  }

  private func loadRootURL(in webView: WKWebView, workspaceID: UUID, reason: String) {
    let request = URLRequest(
      url: baseURL,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 30
    )
    webView.load(request)
    lastKnownState[workspaceID] = .loading
    onStateChange?(workspaceID, .loading)
    scheduleLoadingRecovery(for: webView, workspaceID: workspaceID)
    logger.info(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=load_root duration_ms=0 result=\(reason, privacy: .public)"
    )
  }

  private func scheduleLoadingRecovery(for webView: WKWebView, workspaceID: UUID) {
    let key = ObjectIdentifier(webView)
    loadingRecoveryTasks[key]?.cancel()

    loadingRecoveryTasks[key] = Task { @MainActor [weak self, weak webView] in
      defer {
        self?.loadingRecoveryTasks.removeValue(forKey: key)
      }

      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled else {
        return
      }

      guard
        let self,
        let webView,
        self.webViewWorkspaceMap[ObjectIdentifier(webView)] == workspaceID
      else {
        return
      }

      if webView.isLoading {
        self.logger.warning(
          "workspace_id=\(workspaceID.uuidString, privacy: .public) event=loading_timeout duration_ms=8000 result=recovering"
        )
        webView.stopLoading()
        self.loadRootURL(in: webView, workspaceID: workspaceID, reason: "timeout_recovery")
        return
      }

      let state = await self.detectState(for: webView, workspaceID: workspaceID)
      self.lastKnownState[workspaceID] = state
      self.onStateChange?(workspaceID, state)
      self.refreshUnreadCount(for: webView, workspaceID: workspaceID)
    }
  }

  private func ensureTitleObserver(for webView: WKWebView, workspaceID: UUID) {
    let key = ObjectIdentifier(webView)
    guard titleObservers[key] == nil else {
      return
    }

    titleObservers[key] = webView.observe(\.title, options: [.new, .initial]) { [weak self, weak webView] _, _ in
      Task { @MainActor in
        guard
          let self,
          let webView,
          self.webViewWorkspaceMap[ObjectIdentifier(webView)] == workspaceID
        else {
          return
        }
        self.refreshUnreadCount(for: webView, workspaceID: workspaceID)
      }
    }
  }

  private func refreshUnreadCount(for webView: WKWebView, workspaceID: UUID) {
    let current = unreadCount(fromTitle: webView.title)
    let previous = unreadByWorkspace[workspaceID] ?? 0
    guard current != previous else {
      return
    }

    unreadByWorkspace[workspaceID] = current
    onUnreadCountChange?(workspaceID, previous, current)

    logger.info(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=unread_changed duration_ms=0 result=from=\(previous, privacy: .public)_to=\(current, privacy: .public)"
    )
  }

  private func unreadCount(fromTitle title: String?) -> Int {
    guard let title else {
      return 0
    }

    let pattern = #"^\((\d+)\)"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: title.utf16.count)),
      let numberRange = Range(match.range(at: 1), in: title)
    else {
      return 0
    }

    return Int(title[numberRange]) ?? 0
  }

  private func pointerString(for object: AnyObject) -> String {
    String(describing: Unmanaged.passUnretained(object).toOpaque())
  }

  private func isCancelledNavigationError(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
  }

  private func isTransientNetworkError(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else {
      return false
    }

    return [
      NSURLErrorNetworkConnectionLost,
      NSURLErrorNotConnectedToInternet,
      NSURLErrorTimedOut,
      NSURLErrorCannotFindHost,
      NSURLErrorCannotConnectToHost,
      NSURLErrorDNSLookupFailed
    ].contains(nsError.code)
  }

  private func scheduleDisconnectedRecovery(for webView: WKWebView, workspaceID: UUID) {
    let key = ObjectIdentifier(webView)
    disconnectedRecoveryTasks[key]?.cancel()

    disconnectedRecoveryTasks[key] = Task { @MainActor [weak self, weak webView] in
      defer {
        self?.disconnectedRecoveryTasks.removeValue(forKey: key)
      }

      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else {
        return
      }

      guard
        let self,
        let webView,
        self.webViewWorkspaceMap[ObjectIdentifier(webView)] == workspaceID
      else {
        return
      }
      self.loadRootURL(in: webView, workspaceID: workspaceID, reason: "network_recovery")
    }
  }
}
