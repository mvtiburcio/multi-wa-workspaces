import Foundation
import WorkspaceBridgeContracts

public struct MockSessionBridgeClient: SessionBridgeClient {
  private let seedDate = Date(timeIntervalSince1970: 1_713_800_000)
  private let workspaces: [WorkspaceSnapshot]
  private let conversationsByWorkspace: [UUID: [ConversationSummary]]
  private let messagesByWorkspaceAndConversation: [UUID: [String: [ThreadMessage]]]

  public init() {
    let workspaceA = WorkspaceSnapshot(
      id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
      name: "Operação",
      connectivity: .connected,
      unreadTotal: 3,
      lastSyncAt: seedDate,
      workerState: .running
    )
    let workspaceB = WorkspaceSnapshot(
      id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
      name: "Suporte",
      connectivity: .connected,
      unreadTotal: 1,
      lastSyncAt: seedDate,
      workerState: .running
    )

    workspaces = [workspaceA, workspaceB]

    let convA1 = ConversationSummary(
      id: "op-1",
      workspaceID: workspaceA.id,
      title: "Cliente 101",
      avatarURL: nil,
      lastMessagePreview: "Consegue me atualizar?",
      lastMessageAt: seedDate.addingTimeInterval(60),
      unreadCount: 2,
      pinRank: 1,
      muteUntil: nil,
      status: .active
    )
    let convA2 = ConversationSummary(
      id: "op-2",
      workspaceID: workspaceA.id,
      title: "Cliente 202",
      avatarURL: nil,
      lastMessagePreview: "Pedido confirmado.",
      lastMessageAt: seedDate,
      unreadCount: 1,
      pinRank: nil,
      muteUntil: nil,
      status: .active
    )
    let convB1 = ConversationSummary(
      id: "sup-1",
      workspaceID: workspaceB.id,
      title: "Atendimento",
      avatarURL: nil,
      lastMessagePreview: "Ticket recebido.",
      lastMessageAt: seedDate.addingTimeInterval(30),
      unreadCount: 1,
      pinRank: nil,
      muteUntil: nil,
      status: .active
    )

    conversationsByWorkspace = [
      workspaceA.id: [convA1, convA2],
      workspaceB.id: [convB1]
    ]

    messagesByWorkspaceAndConversation = [
      workspaceA.id: [
        "op-1": [
          ThreadMessage(
            id: "msg-op-1",
            workspaceID: workspaceA.id,
            conversationID: "op-1",
            direction: .incoming,
            authorDisplayName: "Cliente 101",
            content: .text("Consegue me atualizar?"),
            sentAt: seedDate.addingTimeInterval(60),
            delivery: .read
          )
        ],
        "op-2": [
          ThreadMessage(
            id: "msg-op-2",
            workspaceID: workspaceA.id,
            conversationID: "op-2",
            direction: .incoming,
            authorDisplayName: "Cliente 202",
            content: .text("Pedido confirmado."),
            sentAt: seedDate,
            delivery: .read
          )
        ]
      ],
      workspaceB.id: [
        "sup-1": [
          ThreadMessage(
            id: "msg-sup-1",
            workspaceID: workspaceB.id,
            conversationID: "sup-1",
            direction: .incoming,
            authorDisplayName: "Atendimento",
            content: .text("Ticket recebido."),
            sentAt: seedDate.addingTimeInterval(30),
            delivery: .read
          )
        ]
      ]
    ]
  }

  public func fetchWorkspaceList() async throws -> [WorkspaceSnapshot] {
    workspaces
  }

  public func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceSnapshot {
    WorkspaceSnapshot(
      id: UUID(),
      name: request.name,
      connectivity: .qrRequired,
      unreadTotal: 0,
      lastSyncAt: Date(),
      workerState: .provisioning
    )
  }

  public func fetchSnapshot(for workspaceID: UUID) async throws -> BridgeEnvelope<SyncSnapshotPayload> {
    guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
      throw MockBridgeError.workspaceNotFound
    }

    let payload = SyncSnapshotPayload(
      workspace: workspace,
      conversations: conversationsByWorkspace[workspaceID] ?? [],
      messages: messagesByWorkspaceAndConversation[workspaceID] ?? [:],
      cursor: SyncCursor(
        workspaceID: workspaceID,
        sequence: 1,
        lastEventID: "evt-\(workspaceID.uuidString.prefix(4))",
        checkpointAt: seedDate
      )
    )

    return BridgeEnvelope(
      eventID: "sync-\(workspaceID.uuidString)",
      emittedAt: seedDate,
      payload: payload
    )
  }

  public func events(for workspaceID: UUID) -> AsyncThrowingStream<BridgeEnvelope<SyncDeltaPayload>, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        try? await Task.sleep(for: .milliseconds(150))

        let now = seedDate.addingTimeInterval(120)
        let updatedWorkspace = WorkspaceSnapshot(
          id: workspaceID,
          name: (workspaces.first(where: { $0.id == workspaceID })?.name ?? "Workspace"),
          connectivity: .connected,
          unreadTotal: 0,
          lastSyncAt: now,
          workerState: .running
        )

        let cursor = SyncCursor(workspaceID: workspaceID, sequence: 2, lastEventID: "evt-2", checkpointAt: now)
        let payload = SyncDeltaPayload(
          workspaceID: workspaceID,
          events: [
            .workspaceUpdated(updatedWorkspace),
            .syncCheckpoint(cursor)
          ],
          cursor: cursor
        )

        continuation.yield(BridgeEnvelope(eventID: "evt-2", emittedAt: now, payload: payload))
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  public func fetchQRCode(for workspaceID: UUID) async throws -> BridgeEnvelope<WorkspaceQRState> {
    BridgeEnvelope(
      eventID: "qr-\(workspaceID.uuidString)",
      emittedAt: Date(),
      payload: WorkspaceQRState(
        workspaceID: workspaceID,
        state: .pending,
        qrPayload: "WASPACES-MOCK-QR-\(workspaceID.uuidString)",
        expiresAt: Date().addingTimeInterval(60)
      )
    )
  }

  public func send(_ command: SendMessageCommand) async throws -> SendMessageResult {
    let normalizedText = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedText.lowercased().contains("falha") {
      return SendMessageResult(
        clientMessageID: command.clientMessageID,
        providerMessageID: nil,
        accepted: false,
        failureReason: "mock_send_failure",
        processedAt: Date()
      )
    }

    return SendMessageResult(
      clientMessageID: command.clientMessageID,
      providerMessageID: "provider-\(command.clientMessageID.uuidString)",
      accepted: true,
      failureReason: nil,
      processedAt: Date()
    )
  }
}

public enum MockBridgeError: Error {
  case workspaceNotFound
}
