import Combine
import Foundation
import OSLog
import WebKit
import WorkspaceBridgeContracts
import WorkspaceDomain
import WorkspaceSession

@MainActor
public final class WorkspaceManager: ObservableObject, WorkspaceManaging {
  @Published public private(set) var workspaces: [Workspace] = []
  @Published public private(set) var selectedWorkspaceID: UUID?
  @Published public private(set) var selectedWebView: WKWebView?
  @Published public private(set) var unreadByWorkspace: [UUID: Int] = [:]

  public var onWorkspaceNotification: (@MainActor (String, String) -> Void)?

  private let store: WorkspaceStoring
  private let sessionController: WebSessionControlling
  private let logger: Logger
  private let dataStoreRemover: @MainActor @Sendable (UUID) async throws -> Void
  private let enqueuePendingDataStoreRemoval: @MainActor @Sendable (UUID) -> Void
  private let isRecoverableDataStoreRemovalError: @MainActor @Sendable (Error) -> Bool
  private let iconAssetRemover: @MainActor @Sendable (String) async throws -> Void

  private let colorPalette = ["blue", "green", "orange", "red", "teal", "indigo", "pink", "amber"]
  private var isSelectionInFlight = false
  private var queuedSelectionID: UUID?
  private var bridgeRealtimeEnabled = false

  public init(
    store: WorkspaceStoring,
    sessionController: WebSessionControlling,
    logger: Logger = Logger(subsystem: "com.waspaces.app", category: "workspace_manager"),
    dataStoreRemover: @escaping @MainActor @Sendable (UUID) async throws -> Void = { identifier in
      try await WebsiteDataStoreManager.removeDataStore(for: identifier)
    },
    enqueuePendingDataStoreRemoval: @escaping @MainActor @Sendable (UUID) -> Void = { _ in },
    isRecoverableDataStoreRemovalError: @escaping @MainActor @Sendable (Error) -> Bool = { error in
      WebsiteDataStoreManager.isDataStoreInUseError(error)
    },
    iconAssetRemover: @escaping @MainActor @Sendable (String) async throws -> Void = { _ in }
  ) {
    self.store = store
    self.sessionController = sessionController
    self.logger = logger
    self.dataStoreRemover = dataStoreRemover
    self.enqueuePendingDataStoreRemoval = enqueuePendingDataStoreRemoval
    self.isRecoverableDataStoreRemovalError = isRecoverableDataStoreRemovalError
    self.iconAssetRemover = iconAssetRemover

    if let reporter = sessionController as? WebSessionStateReporting {
      reporter.onStateChange = { [weak self] workspaceID, state in
        Task { @MainActor in
          await self?.handleSessionState(workspaceID: workspaceID, state: state)
        }
      }
    }

    if let unreadReporter = sessionController as? WebSessionUnreadReporting {
      unreadReporter.onUnreadCountChange = { [weak self] workspaceID, previous, current in
        Task { @MainActor in
          await self?.handleUnreadCountChanged(workspaceID: workspaceID, previous: previous, current: current)
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

  public func setIconAssetPath(id: UUID, iconAssetPath: String) async throws {
    let startedAt = ContinuousClock.now

    try store.setIconAssetPath(id: id, iconAssetPath: iconAssetPath)
    updateWorkspaceInMemory(id: id) { workspace in
      workspace.iconAssetPath = iconAssetPath
    }

    log(
      event: "workspace_icon_updated",
      workspaceID: id,
      result: "success",
      startedAt: startedAt
    )
  }

  public func clearIconAssetPath(id: UUID) async throws {
    let startedAt = ContinuousClock.now

    try store.clearIconAssetPath(id: id)
    updateWorkspaceInMemory(id: id) { workspace in
      workspace.iconAssetPath = nil
    }

    log(
      event: "workspace_icon_cleared",
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

    let wasSelected = selectedWorkspaceID == id
    if wasSelected {
      // Drop the active WebView reference before teardown so WebKit can release
      // the backing data store/network resources.
      selectedWorkspaceID = nil
      selectedWebView = nil
    }

    do {
      try await sessionController.destroySession(for: id)
    } catch {
      logger.error(
        "workspace_id=\(id.uuidString, privacy: .public) event=workspace_remove_session_failed duration_ms=0 result=\(String(describing: error), privacy: .public)"
      )
      throw WorkspaceError.sessionTeardownFailed(id, String(describing: error))
    }

    if wasSelected {
      // Give SwiftUI/WebKit one run-loop turn to flush view detachment.
      await Task.yield()
    }

    do {
      try await dataStoreRemover(workspace.dataStoreID)
    } catch {
      if isRecoverableDataStoreRemovalError(error) {
        enqueuePendingDataStoreRemoval(workspace.dataStoreID)
        logger.warning(
          "workspace_id=\(id.uuidString, privacy: .public) event=workspace_remove_datastore_recoverable duration_ms=0 result=queued_for_cleanup datastore_id=\(workspace.dataStoreID.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
      } else {
        logger.error(
          "workspace_id=\(id.uuidString, privacy: .public) event=workspace_remove_datastore_failed duration_ms=0 result=\(String(describing: error), privacy: .public)"
        )
        throw WorkspaceError.dataStoreRemovalFailed(id, String(describing: error))
      }
    }

    if let iconAssetPath = workspace.iconAssetPath {
      do {
        try await iconAssetRemover(iconAssetPath)
      } catch {
        logger.error(
          "workspace_id=\(id.uuidString, privacy: .public) event=workspace_remove_icon_cleanup_failed duration_ms=0 result=\(String(describing: error), privacy: .public)"
        )
      }
    }

    try store.delete(id: id)

    try reloadFromStore()

    log(
      event: "workspace_removed",
      workspaceID: id,
      result: "success",
      startedAt: startedAt
    )
  }

  public func select(id: UUID) async throws {
    if isSelectionInFlight {
      queuedSelectionID = id
      return
    }

    isSelectionInFlight = true
    defer {
      isSelectionInFlight = false
      queuedSelectionID = nil
    }

    var targetID: UUID? = id
    while let currentID = targetID {
      queuedSelectionID = nil
      try await performSelect(id: currentID)
      if let nextID = queuedSelectionID, nextID != currentID {
        targetID = nextID
      } else {
        targetID = nil
      }
    }
  }

  public func reloadSelectedWorkspace() async throws {
    guard let selectedWorkspaceID else {
      return
    }

    selectedWebView = nil
    try await sessionController.destroySession(for: selectedWorkspaceID)
    try await performSelect(id: selectedWorkspaceID)
  }

  public func reorder(fromOffsets: IndexSet, toOffset: Int) async throws {
    var reordered = workspaces
    reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)

    try store.reorder(workspaceIDsInDisplayOrder: reordered.map(\.id))
    try reloadFromStore()

    logger.info(
      "workspace_id=none event=workspace_reordered duration_ms=0 result=success"
    )
  }

  private func performSelect(id: UUID) async throws {
    let startedAt = ContinuousClock.now

    guard let workspace = try store.workspace(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }

    if selectedWorkspaceID == id, selectedWebView != nil {
      log(
        event: "workspace_selected",
        workspaceID: id,
        result: "noop_already_selected",
        startedAt: startedAt
      )
      return
    }

    let openedAt = Date()
    try store.updateLastOpenedAt(id: id, date: openedAt)

    let webView = try await sessionController.webView(for: workspace)

    selectedWorkspaceID = id
    selectedWebView = webView
    updateWorkspaceInMemory(id: id) { workspace in
      workspace.lastOpenedAt = openedAt
      if workspace.state == .cold {
        workspace.state = .loading
      }
    }

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

  public func setBridgeRealtimeEnabled(_ enabled: Bool) {
    bridgeRealtimeEnabled = enabled
  }

  public func setWarmWebViewLimit(_ limit: Int?) {
    guard let controller = sessionController as? WebSessionWarmPoolControlling else {
      return
    }
    controller.setWarmWebViewLimit(limit)
  }

  public func currentSessionDiagnostics() -> WebSessionDiagnostics? {
    guard let reporter = sessionController as? WebSessionDiagnosticsReporting else {
      return nil
    }
    return reporter.diagnostics()
  }

  public func applyBridgeWorkspaceSnapshot(_ snapshot: WorkspaceSnapshot) {
    guard workspaces.contains(where: { $0.id == snapshot.id }) else {
      return
    }

    let mappedState = mapBridgeConnectivity(snapshot.connectivity)
    do {
      try store.updateState(id: snapshot.id, state: mappedState)
    } catch {
      logger.error(
        "workspace_id=\(snapshot.id.uuidString, privacy: .public) event=bridge_state_sync duration_ms=0 result=\(String(describing: error), privacy: .public)"
      )
    }

    updateWorkspaceInMemory(id: snapshot.id) { workspace in
      workspace.state = mappedState
    }

    applyUnreadCount(workspaceID: snapshot.id, count: snapshot.unreadTotal, source: "bridge_snapshot")
  }

  public func applyBridgeUnreadCount(workspaceID: UUID, unreadCount: Int) {
    guard workspaces.contains(where: { $0.id == workspaceID }) else {
      return
    }
    applyUnreadCount(workspaceID: workspaceID, count: unreadCount, source: "bridge_realtime")
  }

  private func handleSessionState(workspaceID: UUID, state: WorkspaceState) async {
    if bridgeRealtimeEnabled {
      return
    }

    do {
      try store.updateState(id: workspaceID, state: state)
      updateWorkspaceInMemory(id: workspaceID) { workspace in
        workspace.state = state
      }
    } catch {
      logger.error(
        "workspace_id=\(workspaceID.uuidString, privacy: .public) event=state_sync duration_ms=0 result=\(String(describing: error), privacy: .public)"
      )
    }
  }

  private func handleUnreadCountChanged(workspaceID: UUID, previous: Int, current: Int) async {
    if bridgeRealtimeEnabled {
      return
    }
    applyUnreadCount(workspaceID: workspaceID, count: current, source: "webview_title")
  }

  private func nextColorTag() -> String {
    let usedCount = workspaces.count
    return colorPalette[usedCount % colorPalette.count]
  }

  private func reloadFromStore() throws {
    workspaces = try store.listWorkspaces()
  }

  private func applyUnreadCount(workspaceID: UUID, count: Int, source: String) {
    let previous = unreadByWorkspace[workspaceID] ?? 0
    unreadByWorkspace[workspaceID] = count

    guard count > previous, selectedWorkspaceID != workspaceID else {
      return
    }

    let workspaceName = workspaces.first(where: { $0.id == workspaceID })?.name ?? "Workspace"
    let body = count == 1 ? "1 nova mensagem no workspace." : "\(count) novas mensagens no workspace."
    onWorkspaceNotification?(workspaceName, body)

    logger.info(
      "workspace_id=\(workspaceID.uuidString, privacy: .public) event=workspace_notification duration_ms=0 result=source=\(source, privacy: .public)_unread=\(count, privacy: .public)"
    )
  }

  private func mapBridgeConnectivity(_ state: ConnectivityState) -> WorkspaceState {
    switch state {
    case .cold:
      .cold
    case .connecting:
      .loading
    case .qrRequired:
      .qrRequired
    case .connected:
      .connected
    case .degraded:
      .disconnected
    case .disconnected:
      .disconnected
    }
  }

  private func updateWorkspaceInMemory(id: UUID, mutate: (inout Workspace) -> Void) {
    guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
      return
    }
    var workspace = workspaces[index]
    mutate(&workspace)
    workspaces[index] = workspace
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
