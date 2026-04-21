import Foundation
import Testing
@testable import WorkspacePersistence
import WorkspaceDomain

@MainActor
struct SwiftDataWorkspaceStoreTests {
  @Test
  func insertAndListWorkspaces() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    let workspace = Workspace(name: "Alpha", colorTag: "blue")
    try store.insert(workspace)

    let items = try store.listWorkspaces()
    #expect(items.count == 1)
    #expect(items.first?.name == "Alpha")
    #expect(items.first?.dataStoreID == workspace.dataStoreID)
  }

  @Test
  func renameOnlyChangesTargetWorkspace() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    let alpha = Workspace(name: "Alpha", colorTag: "blue")
    let beta = Workspace(name: "Beta", colorTag: "green")
    try store.insert(alpha)
    try store.insert(beta)

    try store.rename(id: alpha.id, newName: "Alpha Prime")

    let items = try store.listWorkspaces()
    let updatedAlpha = items.first { $0.id == alpha.id }
    let untouchedBeta = items.first { $0.id == beta.id }

    #expect(updatedAlpha?.name == "Alpha Prime")
    #expect(untouchedBeta?.name == "Beta")
  }

  @Test
  func updateStatePersists() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    let workspace = Workspace(name: "Gamma", colorTag: "orange")
    try store.insert(workspace)
    try store.updateState(id: workspace.id, state: .connected)

    let loaded = try store.workspace(id: workspace.id)
    #expect(loaded?.state == .connected)
  }
}
