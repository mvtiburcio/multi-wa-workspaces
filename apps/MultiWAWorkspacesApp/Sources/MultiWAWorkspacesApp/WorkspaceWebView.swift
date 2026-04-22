import SwiftUI
import WebKit

final class WorkspaceWebContainerView: NSView {
  private var hostedWebView: WKWebView?

  func setHostedWebView(_ webView: WKWebView) {
    guard hostedWebView !== webView else {
      return
    }

    hostedWebView?.removeFromSuperview()
    hostedWebView = webView

    addSubview(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: topAnchor),
      webView.leadingAnchor.constraint(equalTo: leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }
}

struct WorkspaceWebView: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WorkspaceWebContainerView {
    let container = WorkspaceWebContainerView()
    container.setHostedWebView(webView)
    return container
  }

  func updateNSView(_ nsView: WorkspaceWebContainerView, context: Context) {
    nsView.setHostedWebView(webView)
  }
}
