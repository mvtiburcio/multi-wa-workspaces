import Foundation
import OSLog
import WebKit
import WorkspaceDomain

@MainActor
public protocol WebSessionStateReporting: AnyObject {
  var onStateChange: (@MainActor (UUID, WorkspaceState) -> Void)? { get set }
}

@MainActor
public final class WebSessionEngine: NSObject, WebSessionControlling, WebSessionStateReporting {
  public var onStateChange: (@MainActor (UUID, WorkspaceState) -> Void)?

  private let pool: WebViewPool
  private let logger: Logger
  private let baseURL = URL(string: "https://web.whatsapp.com")!
  private var webViewWorkspaceMap: [ObjectIdentifier: UUID] = [:]

  public init(
    pool: WebViewPool = WebViewPool(),
    logger: Logger = Logger(subsystem: "com.multiwa.workspaces", category: "web_session_engine")
  ) {
    self.pool = pool
    self.logger = logger
  }

  public func webView(for workspace: Workspace) async throws -> WKWebView {
    let startedAt = ContinuousClock.now

    let webView = pool.webView(for: workspace)
    webView.navigationDelegate = self
    webViewWorkspaceMap[ObjectIdentifier(webView)] = workspace.id

    if webView.url == nil {
      webView.load(URLRequest(url: baseURL))
    }

    onStateChange?(workspace.id, .loading)
    log(
      event: "webview_ready",
      workspaceID: workspace.id,
      result: "success",
      startedAt: startedAt
    )

    return webView
  }

  public func destroySession(for workspaceID: UUID) async throws {
    let startedAt = ContinuousClock.now

    pool.release(workspaceID: workspaceID)
    webViewWorkspaceMap = webViewWorkspaceMap.filter { $0.value != workspaceID }
    onStateChange?(workspaceID, .cold)

    log(
      event: "session_destroyed",
      workspaceID: workspaceID,
      result: "success",
      startedAt: startedAt
    )
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
    onStateChange?(workspaceID, .loading)
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let workspaceID = webViewWorkspaceMap[ObjectIdentifier(webView)] else {
      return
    }

    Task { @MainActor in
      let state = await detectState(for: webView)
      onStateChange?(workspaceID, state)
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

  private func detectState(for webView: WKWebView) async -> WorkspaceState {
    let script = """
      (() => {
        const hasQR = !!document.querySelector('[data-testid="qrcode"]')
          || !!document.querySelector('canvas[aria-label*="Scan"]')
          || !!document.querySelector('canvas[aria-label*="Escaneie"]');
        const hasChatList = !!document.querySelector('[data-testid="chat-list"]')
          || !!document.querySelector('#pane-side');
        return JSON.stringify({ hasQR, hasChatList });
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

      if hasQR {
        return .qrRequired
      }
      if hasChatList {
        return .connected
      }
      return .connected
    } catch {
      return .connected
    }
  }
}
