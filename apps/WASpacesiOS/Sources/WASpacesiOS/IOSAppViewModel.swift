import Foundation
import WorkspaceBridgeContracts

@MainActor
public final class IOSAppViewModel: ObservableObject {
  public enum RuntimeMode: String {
    case mock
    case live
  }

  @Published public private(set) var workspaces: [WorkspaceSnapshot] = []
  @Published public private(set) var selectedWorkspaceID: UUID?
  @Published public private(set) var conversations: [ConversationSummary] = []
  @Published public private(set) var selectedConversationID: String?
  @Published public private(set) var messages: [ThreadMessage] = []
  @Published public var composerText = ""
  @Published public private(set) var fallbackState: FallbackRenderState = .native
  @Published public private(set) var qrState: WorkspaceQRState?
  @Published public private(set) var telemetryEvents: [String] = []
  @Published public private(set) var isBootstrapping = false
  @Published public private(set) var bootstrapErrorMessage: String?
  @Published public private(set) var updates: [UpdateItem] = []
  @Published public private(set) var calls: [CallItem] = []
  @Published public private(set) var isUpdatesLoading = false
  @Published public private(set) var isCallsLoading = false
  @Published public var isFallbackWebPresented = false
  @Published public private(set) var fallbackWebURL: URL?

  private let workspaceProvider: WorkspaceProvider
  private let chatsProvider: ChatsProvider
  private let updatesProvider: UpdatesProvider
  private let callsProvider: CallsProvider
  private let localStore: WorkspaceLocalStore
  public let runtimeMode: RuntimeMode

  private var realtimeTask: Task<Void, Never>?

  public init(
    workspaceProvider: WorkspaceProvider,
    chatsProvider: ChatsProvider,
    updatesProvider: UpdatesProvider,
    callsProvider: CallsProvider,
    localStore: WorkspaceLocalStore,
    runtimeMode: RuntimeMode
  ) {
    self.workspaceProvider = workspaceProvider
    self.chatsProvider = chatsProvider
    self.updatesProvider = updatesProvider
    self.callsProvider = callsProvider
    self.localStore = localStore
    self.runtimeMode = runtimeMode
  }

  deinit {
    realtimeTask?.cancel()
  }

  public static func makeDemo() -> IOSAppViewModel {
    let config = AppConfiguration.fromEnvironment()
    let client: SessionBridgeClient
    if config.useMockBridge {
      client = MockSessionBridgeClient()
    } else {
      client = HTTPBridgeClient(baseURL: config.bridgeBaseURL, token: config.bridgeToken)
    }

    return IOSAppViewModel(
      workspaceProvider: SessionBridgeWorkspaceProvider(syncProvider: client, qrProvider: client),
      chatsProvider: SessionBridgeChatsProvider(syncProvider: client, realtimeProvider: client, sendProvider: client),
      updatesProvider: MockUpdatesProvider(),
      callsProvider: MockCallsProvider(),
      localStore: WorkspaceLocalStore(),
      runtimeMode: config.useMockBridge ? .mock : .live
    )
  }

  public var selectedWorkspace: WorkspaceSnapshot? {
    guard let selectedWorkspaceID else {
      return nil
    }
    return workspaces.first(where: { $0.id == selectedWorkspaceID })
  }

  public func bootstrap() async {
    if isBootstrapping {
      return
    }

    isBootstrapping = true
    bootstrapErrorMessage = nil

    do {
      let workspaceList = try await workspaceProvider.fetchWorkspaceList()
      workspaces = workspaceList

      guard let first = workspaceList.first else {
        isBootstrapping = false
        return
      }

      try await selectWorkspace(id: first.id)
      isBootstrapping = false
    } catch {
      isBootstrapping = false
      bootstrapErrorMessage = "Falha ao carregar dados iniciais. Verifique a Bridge ou use modo demo."
      recordTelemetry("bootstrap_failed error=\(error)")
    }
  }

  public func selectWorkspace(id: UUID) async throws {
    selectedWorkspaceID = id

    if let cached = await localStore.state(for: id) {
      applyState(cached)
    } else {
      let snapshotEnvelope = try await chatsProvider.fetchSnapshot(for: id)
      await localStore.upsertSnapshot(snapshotEnvelope)
      if let loaded = await localStore.state(for: id) {
        applyState(loaded)
      }
    }

    do {
      qrState = try await workspaceProvider.fetchQRCode(for: id).payload
    } catch {
      qrState = nil
      recordTelemetry("qr_failed workspace_id=\(id.uuidString) error=\(error)")
    }

    await loadSupplementaryData(for: id)
    startRealtime(for: id)
  }

  public func reloadQRCodeForSelectedWorkspace() async {
    guard let selectedWorkspaceID else {
      return
    }
    do {
      qrState = try await workspaceProvider.fetchQRCode(for: selectedWorkspaceID).payload
    } catch {
      recordTelemetry("qr_reload_failed workspace_id=\(selectedWorkspaceID.uuidString) error=\(error)")
    }
  }

  public func selectConversation(id: String) {
    selectedConversationID = id
    guard let workspaceID = selectedWorkspaceID else {
      messages = []
      return
    }

    Task {
      guard let state = await localStore.state(for: workspaceID) else {
        await MainActor.run {
          self.messages = []
        }
        return
      }
      await MainActor.run {
        self.messages = state.messagesByConversation[id] ?? []
      }
    }
  }

  public func sendCurrentMessage() async {
    guard let workspaceID = selectedWorkspaceID,
          let conversationID = selectedConversationID else {
      return
    }

    let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }

    let clientMessageID = UUID()
    if await localStore.isMessageAlreadySent(workspaceID: workspaceID, clientMessageID: clientMessageID) {
      return
    }

    let optimistic = ThreadMessage(
      id: clientMessageID.uuidString,
      workspaceID: workspaceID,
      conversationID: conversationID,
      direction: .outgoing,
      authorDisplayName: "Você",
      content: .text(trimmed),
      sentAt: Date(),
      delivery: .pending
    )

    await localStore.appendOptimisticMessage(optimistic)
    composerText = ""
    if let state = await localStore.state(for: workspaceID) {
      applyState(state)
      selectedConversationID = conversationID
      messages = state.messagesByConversation[conversationID] ?? []
    }

    let command = SendMessageCommand(
      workspaceID: workspaceID,
      conversationID: conversationID,
      clientMessageID: clientMessageID,
      text: trimmed,
      requestedAt: Date()
    )

    do {
      let result = try await chatsProvider.send(command)
      if result.accepted {
        await localStore.markMessageDelivery(
          workspaceID: workspaceID,
          conversationID: conversationID,
          messageID: optimistic.id,
          status: .sent
        )
        await localStore.markMessageSent(workspaceID: workspaceID, clientMessageID: command.clientMessageID)
      } else {
        await localStore.markMessageDelivery(
          workspaceID: workspaceID,
          conversationID: conversationID,
          messageID: optimistic.id,
          status: .failed
        )
      }

      if let state = await localStore.state(for: workspaceID) {
        applyState(state)
        selectedConversationID = conversationID
        messages = state.messagesByConversation[conversationID] ?? []
      }
    } catch {
      await localStore.markMessageDelivery(
        workspaceID: workspaceID,
        conversationID: conversationID,
        messageID: optimistic.id,
        status: .failed
      )
      if let state = await localStore.state(for: workspaceID) {
        applyState(state)
        selectedConversationID = conversationID
        messages = state.messagesByConversation[conversationID] ?? []
      }
      recordTelemetry("send_failed workspace_id=\(workspaceID.uuidString) error=\(error)")
    }
  }

  public func simulateFallbackDegradation() async {
    guard let workspaceID = selectedWorkspaceID else {
      return
    }

    await localStore.setFallbackState(.degraded(reason: "mock_parser_mismatch"), workspaceID: workspaceID)
    if let state = await localStore.state(for: workspaceID) {
      applyState(state)
    }

    await localStore.setFallbackState(
      .webViewFallback(reason: "mock_parser_mismatch", startedAt: Date()),
      workspaceID: workspaceID
    )
    if let state = await localStore.state(for: workspaceID) {
      applyState(state)
    }

    recordTelemetry("fallback_state=webViewFallback workspace_id=\(workspaceID.uuidString)")
  }

  public func recoverFallback() async {
    guard let workspaceID = selectedWorkspaceID else {
      return
    }

    await localStore.setFallbackState(.recovering, workspaceID: workspaceID)
    if let state = await localStore.state(for: workspaceID) {
      applyState(state)
    }

    await localStore.setFallbackState(.native, workspaceID: workspaceID)
    if let state = await localStore.state(for: workspaceID) {
      applyState(state)
    }

    recordTelemetry("fallback_state=native workspace_id=\(workspaceID.uuidString)")
  }

  public func openFallbackWebForCurrentWorkspace() {
    guard let workspaceID = selectedWorkspaceID else {
      return
    }

    let url = URL(string: "https://web.whatsapp.com/?workspace_id=\(workspaceID.uuidString)")
      ?? URL(string: "https://web.whatsapp.com")!

    fallbackWebURL = url
    isFallbackWebPresented = true
    recordTelemetry("fallback_opened workspace_id=\(workspaceID.uuidString)")
  }

  private func startRealtime(for workspaceID: UUID) {
    realtimeTask?.cancel()
    realtimeTask = Task {
      do {
        for try await envelope in chatsProvider.events(for: workspaceID) {
          for event in envelope.payload.events {
            await localStore.applyRealtimeEvent(workspaceID: workspaceID, event: event)
          }
          await localStore.applyRealtimeEvent(
            workspaceID: workspaceID,
            event: .syncCheckpoint(envelope.payload.cursor)
          )

          if Task.isCancelled {
            break
          }

          if let state = await localStore.state(for: workspaceID) {
            await MainActor.run {
              self.applyState(state)
              if let selectedConversationID = self.selectedConversationID {
                self.messages = state.messagesByConversation[selectedConversationID] ?? []
              }
            }
          }
        }
      } catch {
        await localStore.setFallbackState(.degraded(reason: "stream_error"), workspaceID: workspaceID)
        await localStore.setFallbackState(.webViewFallback(reason: "stream_error", startedAt: Date()), workspaceID: workspaceID)
        if let state = await localStore.state(for: workspaceID) {
          await MainActor.run {
            self.applyState(state)
          }
        }
        await MainActor.run {
          self.recordTelemetry("realtime_failed workspace_id=\(workspaceID.uuidString) error=\(error)")
        }
      }
    }
  }

  private func loadSupplementaryData(for workspaceID: UUID) async {
    isUpdatesLoading = true
    isCallsLoading = true

    async let updatesTask = updatesProvider.fetchUpdates(for: workspaceID)
    async let callsTask = callsProvider.fetchCalls(for: workspaceID)

    do {
      let workspaceUpdates = try await updatesTask
      await localStore.replaceUpdates(workspaceUpdates, workspaceID: workspaceID)
    } catch {
      recordTelemetry("updates_failed workspace_id=\(workspaceID.uuidString) error=\(error)")
    }

    do {
      let workspaceCalls = try await callsTask
      await localStore.replaceCalls(workspaceCalls, workspaceID: workspaceID)
    } catch {
      recordTelemetry("calls_failed workspace_id=\(workspaceID.uuidString) error=\(error)")
    }

    updates = await localStore.updates(for: workspaceID)
    calls = await localStore.calls(for: workspaceID)
    isUpdatesLoading = false
    isCallsLoading = false
  }

  private func applyState(_ state: WorkspaceLocalState) {
    fallbackState = state.fallbackState
    conversations = state.conversations

    if selectedConversationID == nil,
       let firstConversationID = state.conversations.first?.id {
      selectedConversationID = firstConversationID
    }

    if let selectedConversationID {
      messages = state.messagesByConversation[selectedConversationID] ?? []
    } else {
      messages = []
    }

    if let index = workspaces.firstIndex(where: { $0.id == state.snapshot.id }) {
      workspaces[index] = state.snapshot
    } else {
      workspaces.append(state.snapshot)
      workspaces.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }

  private func recordTelemetry(_ event: String) {
    telemetryEvents.insert(event, at: 0)
    if telemetryEvents.count > 80 {
      telemetryEvents.removeLast(telemetryEvents.count - 80)
    }
  }
}
