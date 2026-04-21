import Testing
import Foundation
@testable import WorkspaceDomain

struct WorkspaceDomainTests {
  @Test
  func workspaceUsesDefaultColdState() {
    let workspace = Workspace(name: "Alpha", colorTag: "blue")
    #expect(workspace.state == .cold)
  }

  @Test
  func workspaceStateRawValuesStayStable() {
    #expect(WorkspaceState.qrRequired.rawValue == "qrRequired")
    #expect(WorkspaceState.connected.rawValue == "connected")
  }

  @Test
  func workspaceHashIncludesIdentityAndDataStore() {
    let id = UUID()
    let dataStoreID = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)

    let a = Workspace(
      id: id,
      name: "A",
      colorTag: "green",
      dataStoreID: dataStoreID,
      createdAt: createdAt
    )
    let b = Workspace(
      id: id,
      name: "A",
      colorTag: "green",
      dataStoreID: dataStoreID,
      createdAt: createdAt
    )

    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
  }
}
