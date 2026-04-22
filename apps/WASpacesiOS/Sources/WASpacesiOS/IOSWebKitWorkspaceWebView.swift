#if os(iOS)
import SwiftUI
import WebKit

final class IOSWorkspaceWebContainerView: UIView {
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

struct IOSWorkspaceWebView: UIViewRepresentable {
  let webView: WKWebView

  func makeUIView(context: Context) -> IOSWorkspaceWebContainerView {
    let container = IOSWorkspaceWebContainerView()
    container.setHostedWebView(webView)
    return container
  }

  func updateUIView(_ uiView: IOSWorkspaceWebContainerView, context: Context) {
    uiView.setHostedWebView(webView)
  }
}
#endif
