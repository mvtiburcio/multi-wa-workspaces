import Foundation
import Testing
import WebKit
@testable import WorkspaceApplicationServices
import WorkspaceDomain
import WorkspacePersistence

@MainActor
final class IntegrationFakeSessionController: WebSessionControlling {
  private(set) var webViewsByWorkspaceID: [UUID: WKWebView] = [:]
  private(set) var destroyedWorkspaceIDs: [UUID] = []

  func webView(for workspace: Workspace) async throws -> WKWebView {
    if let existing = webViewsByWorkspaceID[workspace.id] {
      return existing
    }
    let view = WKWebView(frame: .zero)
    webViewsByWorkspaceID[workspace.id] = view
    return view
  }

  func destroySession(for workspaceID: UUID) async throws {
    destroyedWorkspaceIDs.append(workspaceID)
    webViewsByWorkspaceID.removeValue(forKey: workspaceID)
  }
}

@MainActor
struct WorkspaceManagerIntegrationTests {
  @Test
  func createThreeAndOpenIndependentSessions() async throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()
    let sessions = IntegrationFakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let a = try await manager.create(name: "A")
    let b = try await manager.create(name: "B")
    let c = try await manager.create(name: "C")

    try await manager.select(id: a.id)
    try await manager.select(id: b.id)
    try await manager.select(id: c.id)

    #expect(sessions.webViewsByWorkspaceID.count == 3)
    let identities = Set(sessions.webViewsByWorkspaceID.values.map { ObjectIdentifier($0) })
    #expect(identities.count == 3)
  }

  @Test
  func restartKeepsWorkspaceDataStoreAssociation() async throws {
    let initialStore = try WorkspaceStoreFactory.makeInMemoryStore()
    let initialSessions = IntegrationFakeSessionController()
    let firstManager = WorkspaceManager(
      store: initialStore,
      sessionController: initialSessions,
      dataStoreRemover: { _ in }
    )

    let first = try await firstManager.create(name: "Alpha")
    let second = try await firstManager.create(name: "Beta")

    let restartedStore = SwiftDataWorkspaceStore(container: initialStore.container)
    let restartedSessions = IntegrationFakeSessionController()
    let secondManager = WorkspaceManager(
      store: restartedStore,
      sessionController: restartedSessions,
      dataStoreRemover: { _ in }
    )

    let loaded = try await secondManager.list()

    #expect(loaded.count == 2)
    #expect(loaded.contains(where: { $0.id == first.id && $0.dataStoreID == first.dataStoreID }))
    #expect(loaded.contains(where: { $0.id == second.id && $0.dataStoreID == second.dataStoreID }))
  }

  @Test
  func removeAuthenticatedWorkspaceInvalidatesOnlyRemovedSession() async throws {
    let store = try WorkspaceStoreFactory.makeInMemoryStore()
    let sessions = IntegrationFakeSessionController()
    let manager = WorkspaceManager(
      store: store,
      sessionController: sessions,
      dataStoreRemover: { _ in }
    )

    let first = try await manager.create(name: "A")
    let second = try await manager.create(name: "B")

    try await manager.select(id: first.id)
    try await manager.select(id: second.id)

    try await manager.remove(id: first.id)

    let loaded = try await manager.list()
    #expect(loaded.count == 1)
    #expect(loaded.first?.id == second.id)
    #expect(sessions.destroyedWorkspaceIDs.contains(first.id))
    #expect(sessions.webViewsByWorkspaceID[first.id] == nil)
    #expect(sessions.webViewsByWorkspaceID[second.id] != nil)
  }
}
