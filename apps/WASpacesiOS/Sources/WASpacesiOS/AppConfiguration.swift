import Foundation
import WorkspaceBridgeClient

public struct AppConfiguration: Sendable {
  public let bridgeBaseURL: URL
  public let bridgeToken: String
  public let useMockBridge: Bool

  public init(
    bridgeBaseURL: URL,
    bridgeToken: String,
    useMockBridge: Bool
  ) {
    self.bridgeBaseURL = bridgeBaseURL
    self.bridgeToken = bridgeToken
    self.useMockBridge = useMockBridge
  }

  public static func fromEnvironment() -> AppConfiguration {
    let shared = BridgeClientConfiguration.fromEnvironment()
    let env = ProcessInfo.processInfo.environment
    let useMockRaw = env["WASPACES_IOS_USE_MOCK"]?.lowercased() ?? "1"
    let useMock = useMockRaw == "1" || useMockRaw == "true" || useMockRaw == "yes"

    return AppConfiguration(bridgeBaseURL: shared.baseURL, bridgeToken: shared.token, useMockBridge: useMock)
  }
}
