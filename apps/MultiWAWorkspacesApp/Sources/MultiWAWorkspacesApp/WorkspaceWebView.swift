import SwiftUI
import WebKit

struct WorkspaceWebView: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WKWebView {
    webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    if nsView !== webView {
      nsView.navigationDelegate = webView.navigationDelegate
    }
  }
}
