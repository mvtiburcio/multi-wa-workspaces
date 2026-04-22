import Foundation
import WebKit

@MainActor
public protocol WorkspaceManaging: AnyObject {
  func list() async throws -> [Workspace]
  func create(name: String) async throws -> Workspace
  func rename(id: UUID, newName: String) async throws
  func setIconAssetPath(id: UUID, iconAssetPath: String) async throws
  func clearIconAssetPath(id: UUID) async throws
  func remove(id: UUID) async throws
  func select(id: UUID) async throws
  func reorder(fromOffsets: IndexSet, toOffset: Int) async throws
}

@MainActor
public protocol WebSessionControlling: AnyObject {
  func webView(for workspace: Workspace) async throws -> WKWebView
  func destroySession(for workspaceID: UUID) async throws
}

@MainActor
public protocol WorkspaceStoring: AnyObject {
  func listWorkspaces() throws -> [Workspace]
  func workspace(id: UUID) throws -> Workspace?
  func insert(_ workspace: Workspace) throws
  func rename(id: UUID, newName: String) throws
  func setIconAssetPath(id: UUID, iconAssetPath: String) throws
  func clearIconAssetPath(id: UUID) throws
  func reorder(workspaceIDsInDisplayOrder: [UUID]) throws
  func updateState(id: UUID, state: WorkspaceState) throws
  func updateLastOpenedAt(id: UUID, date: Date) throws
  func delete(id: UUID) throws
}
