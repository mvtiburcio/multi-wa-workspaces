import Foundation
import WorkspaceBridgeClient

public struct AppConfiguration: Sendable {
  public enum RuntimeSource: String, Sendable {
    case webkitRuntime
    case bridge
  }

  public let bridgeBaseURL: URL
  public let bridgeToken: String
  public let allowInsecureTLS: Bool
  public let runtimeSource: RuntimeSource

  public init(
    bridgeBaseURL: URL,
    bridgeToken: String,
    allowInsecureTLS: Bool,
    runtimeSource: RuntimeSource
  ) {
    self.bridgeBaseURL = bridgeBaseURL
    self.bridgeToken = bridgeToken
    self.allowInsecureTLS = allowInsecureTLS
    self.runtimeSource = runtimeSource
  }

  public static func fromEnvironment() -> AppConfiguration {
    let env = ProcessInfo.processInfo.environment
    let info = Bundle.main.infoDictionary ?? [:]

    let envBaseURL = env["WASPACES_BRIDGE_BASE_URL"]
    let plistBaseURL = info["WASPACES_BRIDGE_BASE_URL"] as? String
    let baseURLString = envBaseURL?.isEmpty == false ? envBaseURL : plistBaseURL
    let baseURL = URL(string: baseURLString ?? "") ?? URL(string: "http://127.0.0.1:8080")!

    let envToken = env["WASPACES_BRIDGE_API_TOKEN"]
    let plistToken = info["WASPACES_BRIDGE_API_TOKEN"] as? String
    let token = (envToken?.isEmpty == false ? envToken : plistToken) ?? "dev-local-token"

    let envInsecure = env["WASPACES_BRIDGE_ALLOW_INSECURE_TLS"]
    let plistInsecure = info["WASPACES_BRIDGE_ALLOW_INSECURE_TLS"] as? Bool
    let allowInsecureTLS = envInsecure == "1" || (envInsecure == nil && (plistInsecure ?? false))

    let envRuntimeSource = env["WASPACES_IOS_RUNTIME_SOURCE"]?.lowercased()
    let runtimeSource: RuntimeSource
    if envRuntimeSource == "bridge" {
      runtimeSource = .bridge
    } else {
      runtimeSource = .webkitRuntime
    }

    return AppConfiguration(
      bridgeBaseURL: baseURL,
      bridgeToken: token,
      allowInsecureTLS: allowInsecureTLS,
      runtimeSource: runtimeSource
    )
  }
}
