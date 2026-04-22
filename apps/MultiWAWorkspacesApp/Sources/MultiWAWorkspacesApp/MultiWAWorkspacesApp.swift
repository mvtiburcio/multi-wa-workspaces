import SwiftUI
import UserNotifications
import WorkspaceApplicationServices
import WorkspaceBridgeClient
import WorkspacePersistence
import WorkspaceSession

@main
struct WASpacesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var manager: WorkspaceManager
  @StateObject private var uiSettingsStore: WorkspaceUISettingsStore
  @StateObject private var runtimeOrchestrator: SessionRuntimeOrchestrator
  @StateObject private var memoryTelemetryMonitor: MemoryTelemetryMonitor
  private let notificationCenter: WorkspaceNotificationCenter
  private let iconAssetStore: WorkspaceIconAssetStore
  private let pendingDataStoreCleanupProcessor: PendingDataStoreCleanupProcessor

  init() {
    do {
      let notificationCenter = WorkspaceNotificationCenter()
      self.notificationCenter = notificationCenter
      let uiSettingsStore = WorkspaceUISettingsStore()
      _uiSettingsStore = StateObject(wrappedValue: uiSettingsStore)
      let iconAssetStore = try WorkspaceIconAssetStore()
      self.iconAssetStore = iconAssetStore
      let pendingCleanupQueue = PendingDataStoreCleanupStore()
      let pendingDataStoreCleanupProcessor = PendingDataStoreCleanupProcessor(
        queueStore: pendingCleanupQueue,
        remover: { identifier in
          try await WebsiteDataStoreManager.removeDataStore(for: identifier)
        },
        isRecoverableError: { error in
          WebsiteDataStoreManager.isDataStoreInUseError(error)
        }
      )
      self.pendingDataStoreCleanupProcessor = pendingDataStoreCleanupProcessor

      let store = try WorkspaceStoreFactory.makeDefaultStore()
      // Keep every created workspace warm for true parallel operation in the POC.
      let session = WebSessionEngine(pool: WebViewPool())
      let manager = WorkspaceManager(
        store: store,
        sessionController: session,
        enqueuePendingDataStoreRemoval: { identifier in
          pendingCleanupQueue.enqueue(identifier)
        },
        iconAssetRemover: { path in
          try iconAssetStore.removeIcon(relativePath: path)
        }
      )
      manager.onWorkspaceNotification = { title, body in
        guard uiSettingsStore.settings.notificationsEnabled else {
          return
        }
        Task { @MainActor in
          await notificationCenter.send(title: title, body: body)
        }
      }

      let runtimeOrchestrator = SessionRuntimeOrchestrator(
        manager: manager,
        settingsStore: uiSettingsStore,
        bridgeConfiguration: .fromEnvironment()
      )

      let memoryTelemetryMonitor = MemoryTelemetryMonitor(
        runtimeModeProvider: { runtimeOrchestrator.activeMode },
        selectedWorkspaceProvider: { manager.selectedWorkspaceID },
        diagnosticsProvider: { manager.currentSessionDiagnostics() }
      )

      _manager = StateObject(wrappedValue: manager)
      _runtimeOrchestrator = StateObject(wrappedValue: runtimeOrchestrator)
      _memoryTelemetryMonitor = StateObject(wrappedValue: memoryTelemetryMonitor)
    } catch {
      fatalError("Falha ao iniciar dependências da aplicação: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      WorkspaceShellView(
        manager: manager,
        iconAssetStore: iconAssetStore,
        uiSettingsStore: uiSettingsStore,
        activeRuntimeMode: runtimeOrchestrator.activeMode,
        processPendingCleanupNow: {
          await pendingDataStoreCleanupProcessor.processPending()
        },
        reloadActiveWorkspaceNow: {
          try await manager.reloadSelectedWorkspace()
        }
      )
        .task {
          await manager.refresh()
          if uiSettingsStore.settings.notificationsEnabled {
            await notificationCenter.prepare()
          }
          await pendingDataStoreCleanupProcessor.processPending()
          await runtimeOrchestrator.workspacesDidChange(manager.workspaces)
          await runtimeOrchestrator.start()
          memoryTelemetryMonitor.start()
        }
        .onReceive(uiSettingsStore.$settings) { settings in
          Task { @MainActor in
            await runtimeOrchestrator.settingsDidChange(settings)
          }
        }
        .onReceive(manager.$workspaces) { workspaces in
          Task { @MainActor in
            await runtimeOrchestrator.workspacesDidChange(workspaces)
          }
        }
        .onDisappear {
          runtimeOrchestrator.stop()
          memoryTelemetryMonitor.stop()
        }
    }
    .defaultSize(width: 1_420, height: 920)
  }
}
