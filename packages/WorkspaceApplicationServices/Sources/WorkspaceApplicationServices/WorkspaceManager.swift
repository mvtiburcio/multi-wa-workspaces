import Combine
import Foundation
import OSLog
import WebKit
import WorkspaceDomain
import WorkspaceSession

@MainActor
public final class WorkspaceManager: ObservableObject, WorkspaceManaging {
  @Published public private(set) var workspaces: [Workspace] = []
  @Published public private(set) var selectedWorkspaceID: UUID?
  @Published public private(set) var selectedWebView: WKWebView?

  private let store: WorkspaceStoring
  private let sessionController: WebSessionControlling
  private let logger: Logger
  private let dataStoreRemover: @MainActor @Sendable (UUID) async throws -> Void

  private let colorPalette = ["blue", "green", "orange", "red", "teal", "indigo", "pink", "amber"]

  public init(
    store: WorkspaceStoring,
    sessionController: WebSessionControlling,
    logger: Logger = Logger(subsystem: "com.multiwa.workspaces", category: "workspace_manager"),
    dataStoreRemover: @escaping @MainActor @Sendable (UUID) async throws -> Void = { identifier in
      try await WebsiteDataStoreManager.removeDataStore(for: identifier)
    }
  ) {
    self.store = store
    self.sessionController = sessionController
    self.logger = logger
    self.dataStoreRemover = dataStoreRemover

    if let reporter = sessionController as? WebSessionStateReporting {
      reporter.onStateChange = { [weak self] workspaceID, state in
        Task { @MainActor in
          await self?.handleSessionState(workspaceID: workspaceID, state: state)
        }
      }
    }
  }

  public func list() async throws -> [Workspace] {
    try reloadFromStore()
    return workspaces
  }

  @discardableResult
  public func create(name: String) async throws -> Workspace {
    let startedAt = ContinuousClock.now

    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw WorkspaceError.invalidWorkspaceName
    }

    let workspace = Workspace(
      name: normalizedName,
      colorTag: nextColorTag()
    )

    try store.insert(workspace)
    try reloadFromStore()

    log(
      event: "workspace_created",
      workspaceID: workspace.id,
      result: "success",
      startedAt: startedAt
    )

    return workspace
  }

  public func rename(id: UUID, newName: String) async throws {
    let startedAt = ContinuousClock.now

    try store.rename(id: id, newName: newName)
    try reloadFromStore()

    log(
      event: "workspace_renamed",
      workspaceID: id,
      result: "success",
      startedAt: startedAt
    )
  }

  public func remove(id: UUID) async throws {
    let startedAt = ContinuousClock.now

    guard let workspace = try store.workspace(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }

    do {
      try await sessionController.destroySession(for: id)
    } catch {
      throw WorkspaceError.sessionTeardownFailed(id, String(describing: error))
    }

    do {
      try await dataStoreRemover(workspace.dataStoreID)
    } catch {
      throw WorkspaceError.dataStoreRemovalFailed(id, String(describing: error))
    }

    try store.delete(id: id)

    if selectedWorkspaceID == id {
      selectedWorkspaceID = nil
      selectedWebView = nil
    }

    try reloadFromStore()

    log(
      event: "workspace_removed",
      workspaceID: id,
      result: "success",
      startedAt: startedAt
    )
  }

  public func select(id: UUID) async throws {
    let startedAt = ContinuousClock.now

    guard var workspace = try store.workspace(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }

    try store.updateState(id: id, state: .loading)
    try store.updateLastOpenedAt(id: id, date: Date())

    workspace.state = .loading
    workspace.lastOpenedAt = Date()

    let webView = try await sessionController.webView(for: workspace)

    selectedWorkspaceID = id
    selectedWebView = webView

    try reloadFromStore()

    log(
      event: "workspace_selected",
      workspaceID: id,
      result: "success",
      startedAt: startedAt
    )
  }

  public func refresh() async {
    do {
      try reloadFromStore()
    } catch {
      logger.error(
        "workspace_id=none event=workspace_refresh duration_ms=0 result=\(String(describing: error), privacy: .public)"
      )
    }
  }

  private func handleSessionState(workspaceID: UUID, state: WorkspaceState) async {
    do {
      try store.updateState(id: workspaceID, state: state)
      try reloadFromStore()
    } catch {
      logger.error(
        "workspace_id=\(workspaceID.uuidString, privacy: .public) event=state_sync duration_ms=0 result=\(String(describing: error), privacy: .public)"
      )
    }
  }

  private func nextColorTag() -> String {
    let usedCount = workspaces.count
    return colorPalette[usedCount % colorPalette.count]
  }

  private func reloadFromStore() throws {
    workspaces = try store.listWorkspaces()
  }

  private func log(
    event: String,
    workspaceID: UUID,
    result: String,
    startedAt: ContinuousClock.Instant
  ) {
    let duration = startedAt.duration(to: ContinuousClock.now)
    let durationMS = Int((Double(duration.components.seconds) * 1_000) + (Double(duration.components.attoseconds) / 1_000_000_000_000_000))

    logger.info(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=\(event, privacy: .public) duration_ms=\(durationMS, privacy: .public) result=\(result, privacy: .public)"
    )
  }
}
