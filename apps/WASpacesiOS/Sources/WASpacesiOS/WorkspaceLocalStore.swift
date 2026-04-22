import Foundation
import WorkspaceBridgeContracts

public struct WorkspaceLocalState: Sendable {
  public var snapshot: WorkspaceSnapshot
  public var conversations: [ConversationSummary]
  public var messagesByConversation: [String: [ThreadMessage]]
  public var cursor: SyncCursor
  public var fallbackState: FallbackRenderState

  public init(
    snapshot: WorkspaceSnapshot,
    conversations: [ConversationSummary],
    messagesByConversation: [String: [ThreadMessage]],
    cursor: SyncCursor,
    fallbackState: FallbackRenderState = .native
  ) {
    self.snapshot = snapshot
    self.conversations = conversations
    self.messagesByConversation = messagesByConversation
    self.cursor = cursor
    self.fallbackState = fallbackState
  }
}

public actor WorkspaceLocalStore {
  private var stateByWorkspace: [UUID: WorkspaceLocalState] = [:]
  private var sentMessageIDsByWorkspace: [UUID: Set<UUID>] = [:]
  private var updatesByWorkspace: [UUID: [UpdateItem]] = [:]
  private var callsByWorkspace: [UUID: [CallItem]] = [:]

  public init() {}

  public func upsertSnapshot(_ envelope: BridgeEnvelope<SyncSnapshotPayload>) {
    let payload = envelope.payload
    stateByWorkspace[payload.workspace.id] = WorkspaceLocalState(
      snapshot: payload.workspace,
      conversations: payload.conversations,
      messagesByConversation: payload.messages,
      cursor: payload.cursor,
      fallbackState: .native
    )
  }

  public func state(for workspaceID: UUID) -> WorkspaceLocalState? {
    stateByWorkspace[workspaceID]
  }

  public func workspaces() -> [WorkspaceSnapshot] {
    stateByWorkspace.values
      .map(\.snapshot)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public func applyRealtimeEvent(workspaceID: UUID, event: RealtimeEvent) {
    guard var state = stateByWorkspace[workspaceID] else {
      return
    }

    switch event {
    case .workspaceUpdated(let snapshot):
      state.snapshot = snapshot
    case .conversationUpserted(let conversation):
      if let index = state.conversations.firstIndex(where: { $0.id == conversation.id }) {
        state.conversations[index] = conversation
      } else {
        state.conversations.append(conversation)
      }
      state.conversations.sort { lhs, rhs in
        let lhsDate = lhs.lastMessageAt ?? .distantPast
        let rhsDate = rhs.lastMessageAt ?? .distantPast
        if lhsDate != rhsDate {
          return lhsDate > rhsDate
        }
        return lhs.id < rhs.id
      }
    case .messageUpserted(let message):
      var thread = state.messagesByConversation[message.conversationID] ?? []
      if let index = thread.firstIndex(where: { $0.id == message.id }) {
        thread[index] = message
      } else {
        thread.append(message)
      }
      thread.sort { $0.sentAt < $1.sentAt }
      state.messagesByConversation[message.conversationID] = thread
    case .messageStatusChanged(let messageID, let status):
      for key in state.messagesByConversation.keys {
        guard var thread = state.messagesByConversation[key] else {
          continue
        }
        guard let index = thread.firstIndex(where: { $0.id == messageID }) else {
          continue
        }
        let current = thread[index]
        thread[index] = ThreadMessage(
          id: current.id,
          workspaceID: current.workspaceID,
          conversationID: current.conversationID,
          direction: current.direction,
          authorDisplayName: current.authorDisplayName,
          content: current.content,
          sentAt: current.sentAt,
          delivery: status
        )
        state.messagesByConversation[key] = thread
        break
      }
    case .syncCheckpoint(let cursor):
      state.cursor = cursor
    }

    stateByWorkspace[workspaceID] = state
  }

  public func setFallbackState(_ fallbackState: FallbackRenderState, workspaceID: UUID) {
    guard var state = stateByWorkspace[workspaceID] else {
      return
    }
    state.fallbackState = fallbackState
    stateByWorkspace[workspaceID] = state
  }

  public func appendOptimisticMessage(_ message: ThreadMessage) {
    guard var state = stateByWorkspace[message.workspaceID] else {
      return
    }
    var thread = state.messagesByConversation[message.conversationID] ?? []
    thread.append(message)
    thread.sort { $0.sentAt < $1.sentAt }
    state.messagesByConversation[message.conversationID] = thread

    if let conversationIndex = state.conversations.firstIndex(where: { $0.id == message.conversationID }) {
      let current = state.conversations[conversationIndex]
      let preview = message.content.previewText
      state.conversations[conversationIndex] = ConversationSummary(
        id: current.id,
        workspaceID: current.workspaceID,
        title: current.title,
        avatarURL: current.avatarURL,
        lastMessagePreview: preview,
        lastMessageAt: message.sentAt,
        unreadCount: current.unreadCount,
        pinRank: current.pinRank,
        muteUntil: current.muteUntil,
        status: current.status
      )
    }

    stateByWorkspace[message.workspaceID] = state
  }

  public func markMessageDelivery(workspaceID: UUID, conversationID: String, messageID: String, status: DeliveryStatus) {
    guard var state = stateByWorkspace[workspaceID] else {
      return
    }
    guard var thread = state.messagesByConversation[conversationID] else {
      return
    }
    guard let index = thread.firstIndex(where: { $0.id == messageID }) else {
      return
    }

    let current = thread[index]
    thread[index] = ThreadMessage(
      id: current.id,
      workspaceID: current.workspaceID,
      conversationID: current.conversationID,
      direction: current.direction,
      authorDisplayName: current.authorDisplayName,
      content: current.content,
      sentAt: current.sentAt,
      delivery: status
    )

    state.messagesByConversation[conversationID] = thread
    stateByWorkspace[workspaceID] = state
  }

  public func isMessageAlreadySent(workspaceID: UUID, clientMessageID: UUID) -> Bool {
    sentMessageIDsByWorkspace[workspaceID, default: []].contains(clientMessageID)
  }

  public func markMessageSent(workspaceID: UUID, clientMessageID: UUID) {
    sentMessageIDsByWorkspace[workspaceID, default: []].insert(clientMessageID)
  }

  public func replaceUpdates(_ updates: [UpdateItem], workspaceID: UUID) {
    updatesByWorkspace[workspaceID] = updates.sorted { $0.timestamp > $1.timestamp }
  }

  public func replaceCalls(_ calls: [CallItem], workspaceID: UUID) {
    callsByWorkspace[workspaceID] = calls.sorted { $0.occurredAt > $1.occurredAt }
  }

  public func updates(for workspaceID: UUID) -> [UpdateItem] {
    updatesByWorkspace[workspaceID] ?? []
  }

  public func calls(for workspaceID: UUID) -> [CallItem] {
    callsByWorkspace[workspaceID] ?? []
  }
}

private extension MessageContent {
  var previewText: String {
    switch self {
    case .text(let text):
      return text
    case .media(_, let caption):
      return caption ?? "[Mídia]"
    case .system(let text):
      return text
    }
  }
}
