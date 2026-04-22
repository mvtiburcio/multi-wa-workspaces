import Foundation
import Testing
@testable import WorkspaceBridgeClient

struct WorkspaceBridgeClientTests {
  @Test
  func bridgeClientConfigurationReadsEnvironment() {
    setenv("WASPACES_BRIDGE_BASE_URL", "http://localhost:9090", 1)
    setenv("WASPACES_BRIDGE_API_TOKEN", "abc123", 1)
    setenv("WASPACES_BRIDGE_RETRY_MAX_ATTEMPTS", "7", 1)
    setenv("WASPACES_BRIDGE_RETRY_INITIAL_DELAY_MS", "300", 1)
    setenv("WASPACES_BRIDGE_RETRY_MAX_DELAY_MS", "12000", 1)
    setenv("WASPACES_BRIDGE_RETRY_BACKOFF", "linear", 1)

    let configuration = BridgeClientConfiguration.fromEnvironment()

    #expect(configuration.baseURL.absoluteString == "http://localhost:9090")
    #expect(configuration.token == "abc123")
    #expect(configuration.retryPolicy.maxAttempts == 7)
    #expect(configuration.retryPolicy.initialDelayMilliseconds == 300)
    #expect(configuration.retryPolicy.maxDelayMilliseconds == 12000)
    #expect(configuration.retryPolicy.backoff.rawValue == "linear")
  }
}
