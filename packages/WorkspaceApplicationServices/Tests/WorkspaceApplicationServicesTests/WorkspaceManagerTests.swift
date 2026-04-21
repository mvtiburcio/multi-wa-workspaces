import Foundation
import Testing
import WebKit
@testable import WorkspaceApplicationServices
import WorkspaceDomain

@MainActor
final class InMemoryWorkspaceStore: WorkspaceStoring {
  private(set) var storage: [UUID: Workspace] = [:]

  func listWorkspaces() throws -> [Workspace] {
    storage.values.sorted { $0.createdAt < $1.createdAt }
  }

  func workspace(id: UUID) throws -> Workspace? {
    storage[id]
  }

  func insert(_ workspace: Workspace) throws {
    storage[workspace.id] = workspace
  }

  func rename(id: UUID, newName: String) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.name = newName
    storage[id] = workspace
  }

  func updateState(id: UUID, state: WorkspaceState) throws {
    guard var workspace = storage[id] else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    workspace.state = state
    storage[id] = workspace
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
}
