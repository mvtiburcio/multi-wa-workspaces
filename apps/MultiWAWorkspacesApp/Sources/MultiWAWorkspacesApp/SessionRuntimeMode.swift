import Foundation

enum SessionRuntimeMode: String, Codable, CaseIterable, Identifiable {
  case localLegacy
  case bridgeRealtime
  case bridgeFallbackWebView

  var id: String { rawValue }

  var title: String {
    switch self {
    case .localLegacy:
      return "Local (legado)"
    case .bridgeRealtime:
      return "Bridge em tempo real"
    case .bridgeFallbackWebView:
      return "Fallback WebView"
    }
  }

  var description: String {
    switch self {
    case .localLegacy:
      return "Mantém o modo atual com múltiplos WKWebView locais."
    case .bridgeRealtime:
      return "Usa stream da bridge para tempo real com menor RAM local."
    case .bridgeFallbackWebView:
      return "Degrada para WebView local com pool reduzido."
    }
  }
}
