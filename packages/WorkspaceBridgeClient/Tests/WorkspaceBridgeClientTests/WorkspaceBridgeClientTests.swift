import Foundation
import Testing
@testable import WorkspaceBridgeClient

struct WorkspaceBridgeClientTests {
  @Test
  func bridgeClientConfigurationReadsEnvironment() {
    setenv("WASPACES_BRIDGE_BASE_URL", "http://localhost:9090", 1)
    setenv("WASPACES_BRIDGE_API_TOKEN", "abc123", 1)

    let configuration = BridgeClientConfiguration.fromEnvironment()

    #expect(configuration.baseURL.absoluteString == "http://localhost:9090")
    #expect(configuration.token == "abc123")
  }
}
