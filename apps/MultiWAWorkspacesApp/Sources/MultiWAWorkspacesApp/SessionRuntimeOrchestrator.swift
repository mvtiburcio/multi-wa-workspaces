import Foundation
import OSLog
import WorkspaceApplicationServices
import WorkspaceBridgeClient
import WorkspaceDomain

@MainActor
final class SessionRuntimeOrchestrator: ObservableObject {
  @Published private(set) var activeMode: SessionRuntimeMode

  private let manager: WorkspaceManager
  private let settingsStore: WorkspaceUISettingsStore
  private let bridgeService: WorkspaceBridgeRealtimeServicing
  private let logger: Logger

  private var recoveryTask: Task<Void, Never>?
  private var latestWorkspaceIDs: [UUID] = []

  init(
    manager: WorkspaceManager,
    settingsStore: WorkspaceUISettingsStore,
    bridgeConfiguration: BridgeClientConfiguration = .fromEnvironment(),
    logger: Logger = Logger(subsystem: "com.waspaces.app", category: "runtime_orchestrator")
  ) {
    self.manager = manager
    self.settingsStore = settingsStore
    self.logger = logger
    self.activeMode = settingsStore.settings.sessionRuntimeMode

    let client = HTTPBridgeClient(configuration: bridgeConfiguration)
    self.bridgeService = WorkspaceBridgeRealtimeService(client: client, manager: manager)
  }

  init(
    manager: WorkspaceManager,
    settingsStore: WorkspaceUISettingsStore,
    bridgeService: WorkspaceBridgeRealtimeServicing,
    logger: Logger = Logger(subsystem: "com.waspaces.app", category: "runtime_orchestrator")
  ) {
    self.manager = manager
    self.settingsStore = settingsStore
    self.bridgeService = bridgeService
    self.logger = logger
    self.activeMode = settingsStore.settings.sessionRuntimeMode
  }

  func start() async {
    await applyRequestedMode(settingsStore.settings.sessionRuntimeMode)
  }

  func stop() {
    recoveryTask?.cancel()
    recoveryTask = nil
    bridgeService.stop()
  }

  func settingsDidChange(_ settings: WorkspaceUISettings) async {
    await applyRequestedMode(settings.sessionRuntimeMode)
  }

  func workspacesDidChange(_ workspaces: [Workspace]) async {
    latestWorkspaceIDs = workspaces.map(\.id)

    if activeMode == .bridgeRealtime {
      await bridgeService.update(workspaceIDs: latestWorkspaceIDs)
    }
  }

  private func applyRequestedMode(_ mode: SessionRuntimeMode) async {
    switch mode {
    case .localLegacy:
      stopBridgeMode()
      manager.setBridgeRealtimeEnabled(false)
      manager.setWarmWebViewLimit(nil)
      activeMode = .localLegacy

    case .bridgeFallbackWebView:
      stopBridgeMode()
      manager.setBridgeRealtimeEnabled(false)
      manager.setWarmWebViewLimit(1)
      activeMode = .bridgeFallbackWebView

    case .bridgeRealtime:
      manager.setWarmWebViewLimit(1)

      do {
        try await bridgeService.start(workspaceIDs: latestWorkspaceIDs)
        manager.setBridgeRealtimeEnabled(true)
        activeMode = .bridgeRealtime
        cancelRecoveryLoop()
      } catch {
        logger.error(
          "workspace_id=none event=bridge_start_failed duration_ms=0 result=\(String(describing: error), privacy: .public)"
        )
        enterFallbackAndScheduleRecovery()
      }
    }
  }

  private func stopBridgeMode() {
    bridgeService.stop()
    cancelRecoveryLoop()
  }

  private func cancelRecoveryLoop() {
    recoveryTask?.cancel()
    recoveryTask = nil
  }

  private func enterFallbackAndScheduleRecovery() {
    manager.setBridgeRealtimeEnabled(false)
    activeMode = .bridgeFallbackWebView

    cancelRecoveryLoop()
    recoveryTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(10))

        guard settingsStore.settings.sessionRuntimeMode == .bridgeRealtime else {
          return
        }

        do {
          try await bridgeService.start(workspaceIDs: latestWorkspaceIDs)
          manager.setBridgeRealtimeEnabled(true)
          activeMode = .bridgeRealtime
          logger.info("workspace_id=none event=bridge_recovery_success duration_ms=0 result=ok")
          return
        } catch {
          logger.warning(
            "workspace_id=none event=bridge_recovery_retry duration_ms=0 result=\(String(describing: error), privacy: .public)"
          )
        }
      }
    }
  }
}
