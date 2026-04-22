import Foundation
import Testing
@testable import WASpacesiOSCore
import WorkspaceBridgeContracts

struct WASpacesiOSTests {
  @Test
  func localStoreKeepsWorkspaceIsolation() async {
    let store = WorkspaceLocalStore()

    let workspaceA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let workspaceB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    let now = Date(timeIntervalSince1970: 1_713_810_000)

    await store.upsertSnapshot(
      BridgeEnvelope(
        eventID: "evt-a",
        emittedAt: now,
        payload: SyncSnapshotPayload(
          workspace: WorkspaceSnapshot(
            id: workspaceA,
            name: "A",
            connectivity: .connected,
            unreadTotal: 0,
            lastSyncAt: now,
            workerState: .running
          ),
          conversations: [
            ConversationSummary(
              id: "conv-a",
              workspaceID: workspaceA,
              title: "Conv A",
              avatarURL: nil,
              lastMessagePreview: "...",
              lastMessageAt: now,
              unreadCount: 0,
              pinRank: nil,
              muteUntil: nil,
              status: .active
            )
          ],
          messages: ["conv-a": []],
          cursor: SyncCursor(workspaceID: workspaceA, sequence: 1, lastEventID: nil, checkpointAt: now)
        )
      )
    )

    await store.upsertSnapshot(
      BridgeEnvelope(
        eventID: "evt-b",
        emittedAt: now,
        payload: SyncSnapshotPayload(
          workspace: WorkspaceSnapshot(
            id: workspaceB,
            name: "B",
            connectivity: .connected,
            unreadTotal: 0,
            lastSyncAt: now,
            workerState: .running
          ),
          conversations: [
            ConversationSummary(
              id: "conv-b",
              workspaceID: workspaceB,
              title: "Conv B",
              avatarURL: nil,
              lastMessagePreview: "...",
              lastMessageAt: now,
              unreadCount: 0,
              pinRank: nil,
              muteUntil: nil,
              status: .active
            )
          ],
          messages: ["conv-b": []],
          cursor: SyncCursor(workspaceID: workspaceB, sequence: 1, lastEventID: nil, checkpointAt: now)
        )
      )
    )

    let outgoing = ThreadMessage(
      id: "out-1",
      workspaceID: workspaceA,
      conversationID: "conv-a",
      direction: .outgoing,
      authorDisplayName: "Você",
      content: .text("ok"),
      sentAt: now,
      delivery: .pending
    )

    await store.appendOptimisticMessage(outgoing)

    let stateA = await store.state(for: workspaceA)
    let stateB = await store.state(for: workspaceB)

    #expect((stateA?.messagesByConversation["conv-a"] ?? []).count == 1)
    #expect((stateB?.messagesByConversation["conv-b"] ?? []).count == 0)
  }

  @Test
  func supplementaryStoreKeepsWorkspaceIsolation() async {
    let store = WorkspaceLocalStore()
    let workspaceA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let workspaceB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    let now = Date(timeIntervalSince1970: 1_713_820_000)

    await store.replaceUpdates([
      UpdateItem(
        id: "a1",
        workspaceID: workspaceA,
        title: "A",
        subtitle: "status",
        timestamp: now,
        kind: .status,
        unread: true
      )
    ], workspaceID: workspaceA)

    await store.replaceCalls([
      CallItem(
        id: "b1",
        workspaceID: workspaceB,
        contactName: "Contato",
        occurredAt: now,
        durationSeconds: 20,
        direction: .incoming
      )
    ], workspaceID: workspaceB)

    let updatesA = await store.updates(for: workspaceA)
    let updatesB = await store.updates(for: workspaceB)
    let callsA = await store.calls(for: workspaceA)
    let callsB = await store.calls(for: workspaceB)

    #expect(updatesA.count == 1)
    #expect(updatesB.isEmpty)
    #expect(callsA.isEmpty)
    #expect(callsB.count == 1)
  }

  @Test
  @MainActor
  func composerTransitionsBetweenPendingSentAndFailed() async {
    let viewModel = makeViewModel()

    await viewModel.bootstrap()
    guard let workspaceID = viewModel.selectedWorkspaceID else {
      Issue.record("Workspace não selecionado")
      return
    }

    guard let firstConversationID = viewModel.conversations.first?.id else {
      Issue.record("Conversa não carregada")
      return
    }

    try? await viewModel.selectWorkspace(id: workspaceID)
    viewModel.selectConversation(id: firstConversationID)

    viewModel.composerText = "mensagem ok"
    await viewModel.sendCurrentMessage()

    #expect(viewModel.messages.last?.delivery == .sent)

    viewModel.composerText = "forçar falha"
    await viewModel.sendCurrentMessage()

    #expect(viewModel.messages.last?.delivery == .failed)
  }

  @Test
  @MainActor
  func integrationFlowSupportsWorkspaceSwitchAndFallbackRecovery() async {
    let viewModel = makeViewModel()

    await viewModel.bootstrap()
    #expect(viewModel.workspaces.count == 2)

    let firstWorkspace = viewModel.workspaces[0].id
    let secondWorkspace = viewModel.workspaces[1].id

    try? await viewModel.selectWorkspace(id: firstWorkspace)
    let firstInboxCount = viewModel.conversations.count

    try? await viewModel.selectWorkspace(id: secondWorkspace)
    let secondInboxCount = viewModel.conversations.count

    #expect(firstInboxCount > 0)
    #expect(secondInboxCount > 0)
    #expect(viewModel.selectedWorkspaceID == secondWorkspace)
    #expect(!viewModel.updates.isEmpty)
    #expect(!viewModel.calls.isEmpty)

    await viewModel.simulateFallbackDegradation()
    if case .webViewFallback = viewModel.fallbackState {
      #expect(Bool(true))
    } else {
      Issue.record("Fallback híbrido não foi acionado")
    }

    viewModel.openFallbackWebForCurrentWorkspace()
    #expect(viewModel.isFallbackWebPresented == true)
    #expect(viewModel.fallbackWebURL != nil)

    await viewModel.recoverFallback()
    if case .native = viewModel.fallbackState {
      #expect(Bool(true))
    } else {
      Issue.record("Fallback não retornou para nativo")
    }

    try? await Task.sleep(for: .milliseconds(250))
    let secondConnectivity = viewModel.workspaces.first(where: { $0.id == secondWorkspace })?.connectivity
    #expect(secondConnectivity == .connected)
  }

  @MainActor
  private func makeViewModel() -> IOSAppViewModel {
    let client = MockSessionBridgeClient()
    return IOSAppViewModel(
      workspaceProvider: SessionBridgeWorkspaceProvider(syncProvider: client, qrProvider: client),
      chatsProvider: SessionBridgeChatsProvider(syncProvider: client, realtimeProvider: client, sendProvider: client),
      updatesProvider: MockUpdatesProvider(),
      callsProvider: MockCallsProvider(),
      localStore: WorkspaceLocalStore(),
      runtimeMode: .live
    )
  }
}
