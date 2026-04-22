import Foundation

public enum ConnectivityState: String, Codable, CaseIterable, Sendable {
  case cold
  case connecting
  case qrRequired
  case connected
  case degraded
  case disconnected
}

public enum WorkerState: String, Codable, CaseIterable, Sendable {
  case provisioning
  case running
  case retrying
  case paused
  case failed
}

public struct WorkspaceSnapshot: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let name: String
  public let connectivity: ConnectivityState
  public let unreadTotal: Int
  public let lastSyncAt: Date?
  public let workerState: WorkerState

  public init(
    id: UUID,
    name: String,
    connectivity: ConnectivityState,
    unreadTotal: Int,
    lastSyncAt: Date?,
    workerState: WorkerState
  ) {
    self.id = id
    self.name = name
    self.connectivity = connectivity
    self.unreadTotal = unreadTotal
    self.lastSyncAt = lastSyncAt
    self.workerState = workerState
  }
}

public enum ConversationStatus: String, Codable, CaseIterable, Sendable {
  case active
  case archived
  case muted
  case blocked
}

public struct ConversationSummary: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let workspaceID: UUID
  public let title: String
  public let avatarURL: URL?
  public let lastMessagePreview: String
  public let lastMessageAt: Date?
  public let unreadCount: Int
  public let pinRank: Int?
  public let muteUntil: Date?
  public let status: ConversationStatus

  public init(
    id: String,
    workspaceID: UUID,
    title: String,
    avatarURL: URL?,
    lastMessagePreview: String,
    lastMessageAt: Date?,
    unreadCount: Int,
    pinRank: Int?,
    muteUntil: Date?,
    status: ConversationStatus
  ) {
    self.id = id
    self.workspaceID = workspaceID
    self.title = title
    self.avatarURL = avatarURL
    self.lastMessagePreview = lastMessagePreview
    self.lastMessageAt = lastMessageAt
    self.unreadCount = unreadCount
    self.pinRank = pinRank
    self.muteUntil = muteUntil
    self.status = status
  }
}

public enum MessageDirection: String, Codable, CaseIterable, Sendable {
  case incoming
  case outgoing
}

public enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
  case pending
  case sent
  case delivered
  case read
  case failed
}

public enum MessageContent: Hashable, Codable, Sendable {
  case text(String)
  case media(url: URL, caption: String?)
  case system(String)
}

public struct ThreadMessage: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let workspaceID: UUID
  public let conversationID: String
  public let direction: MessageDirection
  public let authorDisplayName: String?
  public let content: MessageContent
  public let sentAt: Date
  public let delivery: DeliveryStatus

  public init(
    id: String,
    workspaceID: UUID,
    conversationID: String,
    direction: MessageDirection,
    authorDisplayName: String?,
    content: MessageContent,
    sentAt: Date,
    delivery: DeliveryStatus
  ) {
    self.id = id
    self.workspaceID = workspaceID
    self.conversationID = conversationID
    self.direction = direction
    self.authorDisplayName = authorDisplayName
    self.content = content
    self.sentAt = sentAt
    self.delivery = delivery
  }
}

public struct SyncCursor: Hashable, Codable, Sendable {
  public let workspaceID: UUID
  public let sequence: Int64
  public let lastEventID: String?
  public let checkpointAt: Date

  public init(workspaceID: UUID, sequence: Int64, lastEventID: String?, checkpointAt: Date) {
    self.workspaceID = workspaceID
    self.sequence = sequence
    self.lastEventID = lastEventID
    self.checkpointAt = checkpointAt
  }
}

public struct SendMessageCommand: Hashable, Codable, Sendable {
  public let workspaceID: UUID
  public let conversationID: String
  public let clientMessageID: UUID
  public let text: String
  public let requestedAt: Date

  public init(
    workspaceID: UUID,
    conversationID: String,
    clientMessageID: UUID,
    text: String,
    requestedAt: Date
  ) {
    self.workspaceID = workspaceID
    self.conversationID = conversationID
    self.clientMessageID = clientMessageID
    self.text = text
    self.requestedAt = requestedAt
  }
}

public struct SendMessageResult: Hashable, Codable, Sendable {
  public let clientMessageID: UUID
  public let providerMessageID: String?
  public let accepted: Bool
  public let failureReason: String?
  public let processedAt: Date

  public init(
    clientMessageID: UUID,
    providerMessageID: String?,
    accepted: Bool,
    failureReason: String?,
    processedAt: Date
  ) {
    self.clientMessageID = clientMessageID
    self.providerMessageID = providerMessageID
    self.accepted = accepted
    self.failureReason = failureReason
    self.processedAt = processedAt
  }
}

public enum RealtimeEvent: Hashable, Codable, Sendable {
  case workspaceUpdated(WorkspaceSnapshot)
  case conversationUpserted(ConversationSummary)
  case messageUpserted(ThreadMessage)
  case messageStatusChanged(messageID: String, status: DeliveryStatus)
  case syncCheckpoint(SyncCursor)
}

public enum FallbackRenderState: Hashable, Codable, Sendable {
  case native
  case degraded(reason: String)
  case webViewFallback(reason: String, startedAt: Date)
  case recovering
}

public enum BridgeErrorCode: String, Codable, CaseIterable, Sendable {
  case unauthorized
  case workspaceNotFound
  case rateLimited
  case transientNetwork
  case parserDegraded
  case internalError
}

public struct BridgeErrorEnvelope: Hashable, Codable, Sendable {
  public let schemaVersion: Int
  public let code: BridgeErrorCode
  public let message: String
  public let retryAfterMilliseconds: Int?

  public init(
    schemaVersion: Int = BridgeEnvelopeDefaults.schemaVersion,
    code: BridgeErrorCode,
    message: String,
    retryAfterMilliseconds: Int? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.code = code
    self.message = message
    self.retryAfterMilliseconds = retryAfterMilliseconds
  }
}

public enum BridgeEnvelopeDefaults {
  public static let schemaVersion = 1
}

public struct SyncSnapshotPayload: Hashable, Codable, Sendable {
  public let workspace: WorkspaceSnapshot
  public let conversations: [ConversationSummary]
  public let messages: [String: [ThreadMessage]]
  public let cursor: SyncCursor

  public init(
    workspace: WorkspaceSnapshot,
    conversations: [ConversationSummary],
    messages: [String: [ThreadMessage]],
    cursor: SyncCursor
  ) {
    self.workspace = workspace
    self.conversations = conversations
    self.messages = messages
    self.cursor = cursor
  }
}

public struct SyncDeltaPayload: Hashable, Codable, Sendable {
  public let workspaceID: UUID
  public let events: [RealtimeEvent]
  public let cursor: SyncCursor

  public init(workspaceID: UUID, events: [RealtimeEvent], cursor: SyncCursor) {
    self.workspaceID = workspaceID
    self.events = events
    self.cursor = cursor
  }
}

public enum QRConnectionState: String, Codable, CaseIterable, Sendable {
  case pending
  case scanned
  case linked
  case expired
}

public struct WorkspaceQRState: Hashable, Codable, Sendable {
  public let workspaceID: UUID
  public let state: QRConnectionState
  public let qrPayload: String
  public let expiresAt: Date

  public init(workspaceID: UUID, state: QRConnectionState, qrPayload: String, expiresAt: Date) {
    self.workspaceID = workspaceID
    self.state = state
    self.qrPayload = qrPayload
    self.expiresAt = expiresAt
  }
}

public struct BridgeEnvelope<Payload: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
  public let schemaVersion: Int
  public let eventID: String
  public let emittedAt: Date
  public let payload: Payload

  public init(
    schemaVersion: Int = BridgeEnvelopeDefaults.schemaVersion,
    eventID: String,
    emittedAt: Date,
    payload: Payload
  ) {
    self.schemaVersion = schemaVersion
    self.eventID = eventID
    self.emittedAt = emittedAt
    self.payload = payload
  }
}

public enum BridgeRetryBackoff: String, Codable, CaseIterable, Sendable {
  case none
  case linear
  case exponential
}

public struct BridgeRetryPolicy: Hashable, Codable, Sendable {
  public let maxAttempts: Int
  public let initialDelayMilliseconds: Int
  public let maxDelayMilliseconds: Int
  public let backoff: BridgeRetryBackoff

  public init(
    maxAttempts: Int,
    initialDelayMilliseconds: Int,
    maxDelayMilliseconds: Int,
    backoff: BridgeRetryBackoff
  ) {
    self.maxAttempts = maxAttempts
    self.initialDelayMilliseconds = initialDelayMilliseconds
    self.maxDelayMilliseconds = maxDelayMilliseconds
    self.backoff = backoff
  }
}
