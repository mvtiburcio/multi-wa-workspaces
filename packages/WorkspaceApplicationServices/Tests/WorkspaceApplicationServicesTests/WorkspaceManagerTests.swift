import Foundation
import Testing
import WebKit
@testable import WorkspaceApplicationServices
import WorkspaceDomain

@MainActor
final class InMemoryWorkspaceStore: WorkspaceStoring {
  private(set) var storage: [UUID: Workspace] = [:]
  private(set) var displayOrder: [UUID] = []
  private(set) var reorderCalls: [[UUID]] = []

  func listWorkspaces() throws -> [Workspace] {
    if displayOrder.isEmpty {
      return storage.values.sorted { $0.createdAt < $1.createdAt }
    }
    return displayOrder.compactMap { storage[$0] }
  }

  func workspace(id: UUID) throws -> Workspace? {
    storage[id]
  }

  func insert(_ workspace: Workspace) throws {
    storage[workspace.id] = workspace
    displayOrder.append(workspace.id)
  }

  func rename(id: UUID, newName: String) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.name = newName
    storage[id] = workspace
  }

  func setIconAssetPath(id: UUID, iconAssetPath: String) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.iconAssetPath = iconAssetPath
    storage[id] = workspace
  }

  func clearIconAssetPath(id: UUID) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.iconAssetPath = nil
    storage[id] = workspace
  }

  func updateState(id: UUID, state: WorkspaceState) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.state = state
    storage[id] = workspace
  }

  func reorder(workspaceIDsInDisplayOrder: [UUID]) throws {
    guard
      workspaceIDsInDisplayOrder.count == storage.count,
      Set(workspaceIDsInDisplayOrder) == Set(storage.keys)
    else {
      throw WorkspaceError.invalidWorkspaceOrder
    }
    displayOrder = workspaceIDsInDisplayOrder
    reorderCalls.append(workspaceIDsInDisplayOrder)
  }

  func updateLastOpenedAt(id: UUID, date: Date) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.lastOpenedAt = date
    storage[id] = workspace
  }

  func delete(id: UUID) throws {
    storage.removeValue(forKey: id)
    displayOrder.removeAll { $0 == id }
  }
}

@MainActor
final class FakeSessionController: WebSessionControlling {
  var webViewsByWorkspaceID: [UUID: WKWebView] = [:]
  private(set) var selectedWorkspaceIDs: [UUID] = []
  private(set) var destroyedWorkspaceIDs: [UUID] = []

  func webView(for workspace: Workspace) async throws -> WKWebView {
    selectedWorkspaceIDs.append(workspace.id)
    if let existing = webViewsByWorkspaceID[workspace.id] {
      return existing
    }
    let webView = WKWebView(frame: .zero)
    webViewsByWorkspaceID[workspace.id] = webView
    return webView
  }

  func destroySession(for workspaceID: UUID) async throws {
    destroyedWorkspaceIDs.append(workspaceID)
    webViewsByWorkspaceID.removeValue(forKey: workspaceID)
  }
}

@MainActor
struct WorkspaceManagerTests {
  private final class ManagerProbe {
    weak var manager: WorkspaceManager?
  }

  @Test
  func createGeneratesUniqueDataStoreID() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let first = try await manager.create(name: "A")
    let second = try await manager.create(name: "B")

    #expect(first.dataStoreID != second.dataStoreID)
  }

  @Test
  func selectDoesNotOverrideOtherSession() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let a = try await manager.create(name: "A")
    let b = try await manager.create(name: "B")

    try await manager.select(id: a.id)
    let webViewA = sessions.webViewsByWorkspaceID[a.id]

    try await manager.select(id: b.id)
    let webViewAAfter = sessions.webViewsByWorkspaceID[a.id]

    #expect(webViewA === webViewAAfter)
    #expect(sessions.selectedWorkspaceIDs == [a.id, b.id])
  }

  @Test
  func removeDeletesMetadataAndSession() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    var removedDataStores: [UUID] = []
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { identifier in
        removedDataStores.append(identifier)
      }
    )

    let workspace = try await manager.create(name: "A")
    try await manager.select(id: workspace.id)
    try await manager.remove(id: workspace.id)

    #expect((try store.workspace(id: workspace.id)) == nil)
    #expect(sessions.destroyedWorkspaceIDs.contains(workspace.id))
    #expect(removedDataStores.contains(workspace.dataStoreID))
  }

  @Test
  func removeClearsSelectionBeforeRemovingDataStore() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let probe = ManagerProbe()
    var selectedWorkspaceIDDuringDataStoreRemoval: UUID?

    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in
        selectedWorkspaceIDDuringDataStoreRemoval = probe.manager?.selectedWorkspaceID
      }
    )
    probe.manager = manager

    let workspace = try await manager.create(name: "A")
    try await manager.select(id: workspace.id)
    try await manager.remove(id: workspace.id)

    #expect(selectedWorkspaceIDDuringDataStoreRemoval == nil)
  }

  @Test
  func renameChangesOnlyTargetWorkspace() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let a = try await manager.create(name: "A")
    let b = try await manager.create(name: "B")

    try await manager.rename(id: a.id, newName: "A Prime")

    let all = try await manager.list()
    #expect(all.first { $0.id == a.id }?.name == "A Prime")
    #expect(all.first { $0.id == b.id }?.name == "B")
  }

  @Test
  func reorderPersistsThroughManager() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let first = try await manager.create(name: "A")
    let second = try await manager.create(name: "B")
    let third = try await manager.create(name: "C")

    try await manager.reorder(fromOffsets: IndexSet(integer: 2), toOffset: 0)

    let ordered = try await manager.list()
    #expect(ordered.map(\.id) == [third.id, first.id, second.id])
    #expect(store.reorderCalls.last == [third.id, first.id, second.id])
  }

  @Test
  func selectSameWorkspaceIsIdempotent() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let workspace = try await manager.create(name: "A")
    try await manager.select(id: workspace.id)
    try await manager.select(id: workspace.id)

    #expect(sessions.selectedWorkspaceIDs == [workspace.id])
  }

  @Test
  func updateIconChangesOnlyTargetWorkspace() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let a = try await manager.create(name: "A")
    let b = try await manager.create(name: "B")

    try await manager.setIconAssetPath(id: a.id, iconAssetPath: "workspace-icons/\(a.id.uuidString).png")

    let all = try await manager.list()
    #expect(all.first(where: { $0.id == a.id })?.iconAssetPath == "workspace-icons/\(a.id.uuidString).png")
    #expect(all.first(where: { $0.id == b.id })?.iconAssetPath == nil)
  }

  @Test
  func removeTriggersIconAssetCleanupWhenWorkspaceHasIcon() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    var removedAssets: [String] = []

    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in },
      iconAssetRemover: { path in
        removedAssets.append(path)
      }
    )

    let workspace = try await manager.create(name: "A")
    try await manager.setIconAssetPath(id: workspace.id, iconAssetPath: "workspace-icons/\(workspace.id.uuidString).png")
    try await manager.remove(id: workspace.id)

    #expect(removedAssets == ["workspace-icons/\(workspace.id.uuidString).png"])
  }

  @Test
  func removeWithRecoverableDatastoreFailureQueuesCleanupAndStillDeletes() async throws {
    struct RecoverableFailure: Error {}

    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    var queuedDataStoreIDs: [UUID] = []

    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in
        throw RecoverableFailure()
      },
      enqueuePendingDataStoreRemoval: { identifier in
        queuedDataStoreIDs.append(identifier)
      },
      isRecoverableDataStoreRemovalError: { error in
        error is RecoverableFailure
      }
    )

    let workspace = try await manager.create(name: "A")
    try await manager.remove(id: workspace.id)

    #expect((try store.workspace(id: workspace.id)) == nil)
    #expect(queuedDataStoreIDs == [workspace.dataStoreID])
  }

  @Test
  func reloadSelectedWorkspaceRecreatesSessionForActiveWorkspace() async throws {
    let store = InMemoryWorkspaceStore()
    let sessions = FakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let workspace = try await manager.create(name: "A")
    try await manager.select(id: workspace.id)
    try await manager.reloadSelectedWorkspace()

    #expect(sessions.destroyedWorkspaceIDs.contains(workspace.id))
    #expect(sessions.selectedWorkspaceIDs == [workspace.id, workspace.id])
  }
}
