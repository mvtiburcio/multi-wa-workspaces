import Foundation
import WorkspaceBridgeContracts

public struct BridgeClientConfiguration: Sendable, Equatable {
  public let baseURL: URL
  public let token: String
  public let retryPolicy: BridgeRetryPolicy
  public let allowInsecureTLS: Bool

  public init(
    baseURL: URL,
    token: String,
    allowInsecureTLS: Bool = false,
    retryPolicy: BridgeRetryPolicy = BridgeRetryPolicy(
      maxAttempts: 5,
      initialDelayMilliseconds: 500,
      maxDelayMilliseconds: 10_000,
      backoff: .exponential
    )
  ) {
    self.baseURL = baseURL
    self.token = token
    self.allowInsecureTLS = allowInsecureTLS
    self.retryPolicy = retryPolicy
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
    let maxAttempts = Int(env["WASPACES_BRIDGE_RETRY_MAX_ATTEMPTS"] ?? "") ?? 5
    let initialDelay = Int(env["WASPACES_BRIDGE_RETRY_INITIAL_DELAY_MS"] ?? "") ?? 500
    let maxDelay = Int(env["WASPACES_BRIDGE_RETRY_MAX_DELAY_MS"] ?? "") ?? 10_000
    let backoffRaw = env["WASPACES_BRIDGE_RETRY_BACKOFF"] ?? BridgeRetryBackoff.exponential.rawValue
    let backoff = BridgeRetryBackoff(rawValue: backoffRaw) ?? .exponential
    let allowInsecureTLS = (env["WASPACES_BRIDGE_ALLOW_INSECURE_TLS"] ?? "") == "1"
    let retryPolicy = BridgeRetryPolicy(
      maxAttempts: max(1, maxAttempts),
      initialDelayMilliseconds: max(0, initialDelay),
      maxDelayMilliseconds: max(0, maxDelay),
      backoff: backoff
    )
    return BridgeClientConfiguration(
      baseURL: resolvedBaseURL,
      token: token,
      allowInsecureTLS: allowInsecureTLS,
      retryPolicy: retryPolicy
    )
  }
}
