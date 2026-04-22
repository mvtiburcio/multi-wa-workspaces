import Foundation
import SwiftData
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

  @Test
  func insertAssignsIncreasingSortOrder() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    try store.insert(Workspace(name: "A", colorTag: "blue"))
    try store.insert(Workspace(name: "B", colorTag: "green"))
    try store.insert(Workspace(name: "C", colorTag: "orange"))

    let context = ModelContext(store.container)
    let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
    let sortOrders = records.compactMap(\.sortOrder).sorted()

    #expect(sortOrders == [0, 1, 2])
  }

  @Test
  func reorderPersistsOrder() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    let first = Workspace(name: "A", colorTag: "blue")
    let second = Workspace(name: "B", colorTag: "green")
    let third = Workspace(name: "C", colorTag: "orange")
    try store.insert(first)
    try store.insert(second)
    try store.insert(third)

    try store.reorder(workspaceIDsInDisplayOrder: [third.id, first.id, second.id])

    let ordered = try store.listWorkspaces()
    #expect(ordered.map(\.id) == [third.id, first.id, second.id])
  }

  @Test
  func setAndClearIconAssetPath() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    let workspace = Workspace(name: "A", colorTag: "blue")
    try store.insert(workspace)

    let iconPath = "workspace-icons/\(workspace.id.uuidString).png"
    try store.setIconAssetPath(id: workspace.id, iconAssetPath: iconPath)
    #expect(try store.workspace(id: workspace.id)?.iconAssetPath == iconPath)

    try store.clearIconAssetPath(id: workspace.id)
    #expect(try store.workspace(id: workspace.id)?.iconAssetPath == nil)
  }

  @Test
  func reorderKeepsIconMetadata() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()

    let first = Workspace(name: "A", colorTag: "blue")
    let second = Workspace(name: "B", colorTag: "green")
    try store.insert(first)
    try store.insert(second)
    try store.setIconAssetPath(id: second.id, iconAssetPath: "workspace-icons/\(second.id.uuidString).png")

    try store.reorder(workspaceIDsInDisplayOrder: [second.id, first.id])

    let ordered = try store.listWorkspaces()
    #expect(ordered.map(\.id) == [second.id, first.id])
    #expect(ordered.first?.iconAssetPath == "workspace-icons/\(second.id.uuidString).png")
  }

  @Test
  func backfillLegacyRowsUsesDeterministicOrder() throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()
    let context = ModelContext(store.container)
    context.autosaveEnabled = false

    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = older.addingTimeInterval(1)

    let legacyA = WorkspaceRecord(
      id: UUID(),
      name: "Beta",
      colorTag: "blue",
      dataStoreID: UUID(),
      stateRawValue: WorkspaceState.cold.rawValue,
      sortOrder: nil,
      iconAssetPath: nil,
      createdAt: older,
      lastOpenedAt: nil
    )
    let legacyB = WorkspaceRecord(
      id: UUID(),
      name: "Alpha",
      colorTag: "green",
      dataStoreID: UUID(),
      stateRawValue: WorkspaceState.cold.rawValue,
      sortOrder: nil,
      iconAssetPath: nil,
      createdAt: older,
      lastOpenedAt: nil
    )
    let legacyC = WorkspaceRecord(
      id: UUID(),
      name: "Gamma",
      colorTag: "orange",
      dataStoreID: UUID(),
      stateRawValue: WorkspaceState.cold.rawValue,
      sortOrder: nil,
      iconAssetPath: nil,
      createdAt: newer,
      lastOpenedAt: nil
    )

    context.insert(legacyA)
    context.insert(legacyB)
    context.insert(legacyC)
    try context.save()

    let loaded = try store.listWorkspaces()
    #expect(loaded.map(\.id) == [legacyB.id, legacyA.id, legacyC.id])

    let refreshedRecords = try context.fetch(FetchDescriptor<WorkspaceRecord>())
    #expect(refreshedRecords.allSatisfy { $0.sortOrder != nil })
  }
}
