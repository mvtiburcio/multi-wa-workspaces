import Foundation

public struct BridgeClientConfiguration: Sendable, Equatable {
  public let baseURL: URL
  public let token: String

  public init(baseURL: URL, token: String) {
    self.baseURL = baseURL
    self.token = token
  }

  public static func fromEnvironment(
    processInfo: ProcessInfo = .processInfo,
    baseURLKey: String = "WASPACES_BRIDGE_BASE_URL",
    tokenKey: String = "WASPACES_BRIDGE_API_TOKEN"
  ) -> BridgeClientConfiguration {
    let env = processInfo.environment
    let defaultURL = URL(string: "http://127.0.0.1:8080")!
    let resolvedBaseURL = URL(string: env[baseURLKey] ?? "") ?? defaultURL
    let token = env[tokenKey] ?? "dev-local-token"
    return BridgeClientConfiguration(baseURL: resolvedBaseURL, token: token)
  }
}
