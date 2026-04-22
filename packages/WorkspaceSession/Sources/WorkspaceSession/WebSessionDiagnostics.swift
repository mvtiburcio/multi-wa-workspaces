import Foundation

public struct WebSessionDiagnostics: Sendable, Equatable {
  public let cachedWebViewCount: Int
  public let trackedWebViewCount: Int
  public let trackedWorkspaceCount: Int

  public init(
    cachedWebViewCount: Int,
    trackedWebViewCount: Int,
    trackedWorkspaceCount: Int
  ) {
    self.cachedWebViewCount = cachedWebViewCount
    self.trackedWebViewCount = trackedWebViewCount
    self.trackedWorkspaceCount = trackedWorkspaceCount
  }
}

@MainActor
public protocol WebSessionDiagnosticsReporting: AnyObject {
  func diagnostics() -> WebSessionDiagnostics
}

@MainActor
public protocol WebSessionWarmPoolControlling: AnyObject {
  func setWarmWebViewLimit(_ limit: Int?)
}
