import Fluent
import FluentSQLiteDriver
import Foundation
import Vapor
import WorkspaceBridgeContracts

@main
enum SessionBridgeServerMain {
  static func main() async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)
    let app = try await Application.make(env)

    try configure(app)
    try await app.execute()
    try await app.asyncShutdown()
  }
}

func configure(_ app: Application) throws {
  let databasePath = Environment.get("WASPACES_BRIDGE_DB_PATH") ?? "bridge-session.sqlite"
  app.databases.use(.sqlite(.file(databasePath)), as: .sqlite)

  app.migrations.add(CreateWorkspaceMigration())
  app.migrations.add(CreateConversationMigration())
  app.migrations.add(CreateMessageMigration())
  app.migrations.add(CreateCommandDedupeMigration())
  app.migrations.add(CreateEventLogMigration())

  try app.autoMigrate().wait()
  try seedIfNeeded(on: app.db)

  app.middleware.use(BridgeAuthMiddleware(token: Environment.get("WASPACES_BRIDGE_API_TOKEN") ?? "dev-local-token"))
  try routes(app)
}

private struct BridgeAuthMiddleware: AsyncMiddleware {
  let token: String

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    guard let authorization = request.headers.bearerAuthorization?.token, authorization == token else {
      throw Abort(.unauthorized, reason: "invalid bearer token")
    }
    return try await next.respond(to: request)
  }
}

final class BridgeWorkspace: Model, @unchecked Sendable {
  static let schema = "bridge_workspaces"

  @ID(key: .id) var id: UUID?
  @Field(key: "name") var name: String
  @Field(key: "connectivity") var connectivity: String
  @Field(key: "unread_total") var unreadTotal: Int
  @Field(key: "worker_state") var workerState: String
  @Field(key: "qr_payload") var qrPayload: String
  @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

  init() {}

  init(id: UUID, name: String, connectivity: String, unreadTotal: Int, workerState: String, qrPayload: String) {
    self.id = id
    self.name = name
    self.connectivity = connectivity
    self.unreadTotal = unreadTotal
    self.workerState = workerState
    self.qrPayload = qrPayload
  }
}

final class BridgeConversation: Model, @unchecked Sendable {
  static let schema = "bridge_conversations"

  @ID(custom: "id", generatedBy: .user) var id: String?
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "title") var title: String
  @Field(key: "last_message_preview") var lastMessagePreview: String
  @Field(key: "unread_count") var unreadCount: Int
  @Field(key: "status") var status: String
  @Timestamp(key: "last_message_at", on: .none) var lastMessageAt: Date?

  init() {}

  init(id: String, workspaceID: UUID, title: String, lastMessagePreview: String, unreadCount: Int, status: String, lastMessageAt: Date?) {
    self.id = id
    self.workspaceID = workspaceID
    self.title = title
    self.lastMessagePreview = lastMessagePreview
    self.unreadCount = unreadCount
    self.status = status
    self.lastMessageAt = lastMessageAt
  }
}

final class BridgeMessage: Model, @unchecked Sendable {
  static let schema = "bridge_messages"

  @ID(custom: "id", generatedBy: .user) var id: String?
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "conversation_id") var conversationID: String
  @Field(key: "direction") var direction: String
  @Field(key: "author_display_name") var authorDisplayName: String?
  @Field(key: "content_text") var contentText: String
  @Timestamp(key: "sent_at", on: .none) var sentAt: Date?
  @Field(key: "delivery") var delivery: String

  init() {}

  init(
    id: String,
    workspaceID: UUID,
    conversationID: String,
    direction: String,
    authorDisplayName: String?,
    contentText: String,
    sentAt: Date,
    delivery: String
  ) {
    self.id = id
    self.workspaceID = workspaceID
    self.conversationID = conversationID
    self.direction = direction
    self.authorDisplayName = authorDisplayName
    self.contentText = contentText
    self.sentAt = sentAt
    self.delivery = delivery
  }
}

final class BridgeCommandDedupe: Model, @unchecked Sendable {
  static let schema = "bridge_command_dedupe"

  @ID(key: .id) var id: UUID?
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "client_message_id") var clientMessageID: UUID
  @Field(key: "provider_message_id") var providerMessageID: String?
  @Field(key: "accepted") var accepted: Bool
  @Field(key: "failure_reason") var failureReason: String?
  @Timestamp(key: "processed_at", on: .none) var processedAt: Date?

  init() {}

  init(workspaceID: UUID, clientMessageID: UUID, providerMessageID: String?, accepted: Bool, failureReason: String?, processedAt: Date) {
    self.workspaceID = workspaceID
    self.clientMessageID = clientMessageID
    self.providerMessageID = providerMessageID
    self.accepted = accepted
    self.failureReason = failureReason
    self.processedAt = processedAt
  }
}

final class BridgeEventLog: Model, @unchecked Sendable {
  static let schema = "bridge_event_logs"

  @ID(key: .id) var id: UUID?
  @Field(key: "sequence") var sequence: Int64
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "event_id") var eventID: String
  @Field(key: "event_json") var eventJSON: String
  @Timestamp(key: "created_at", on: .none) var createdAt: Date?

  init() {}

  init(sequence: Int64, workspaceID: UUID, eventID: String, eventJSON: String, createdAt: Date) {
    self.sequence = sequence
    self.workspaceID = workspaceID
    self.eventID = eventID
    self.eventJSON = eventJSON
    self.createdAt = createdAt
  }
}

struct CreateWorkspaceMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeWorkspace.schema)
      .id()
      .field("name", .string, .required)
      .field("connectivity", .string, .required)
      .field("unread_total", .int, .required)
      .field("worker_state", .string, .required)
      .field("qr_payload", .string, .required)
      .field("updated_at", .datetime)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeWorkspace.schema).delete()
  }
}

struct CreateConversationMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeConversation.schema)
      .field("id", .string, .identifier(auto: false))
      .field("workspace_id", .uuid, .required)
      .field("title", .string, .required)
      .field("last_message_preview", .string, .required)
      .field("unread_count", .int, .required)
      .field("status", .string, .required)
      .field("last_message_at", .datetime)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeConversation.schema).delete()
  }
}

struct CreateMessageMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeMessage.schema)
      .field("id", .string, .identifier(auto: false))
      .field("workspace_id", .uuid, .required)
      .field("conversation_id", .string, .required)
      .field("direction", .string, .required)
      .field("author_display_name", .string)
      .field("content_text", .string, .required)
      .field("sent_at", .datetime)
      .field("delivery", .string, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeMessage.schema).delete()
  }
}

struct CreateCommandDedupeMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeCommandDedupe.schema)
      .id()
      .field("workspace_id", .uuid, .required)
      .field("client_message_id", .uuid, .required)
      .field("provider_message_id", .string)
      .field("accepted", .bool, .required)
      .field("failure_reason", .string)
      .field("processed_at", .datetime)
      .unique(on: "workspace_id", "client_message_id")
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeCommandDedupe.schema).delete()
  }
}

struct CreateEventLogMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeEventLog.schema)
      .id()
      .field("sequence", .int64, .required)
      .field("workspace_id", .uuid, .required)
      .field("event_id", .string, .required)
      .field("event_json", .string, .required)
      .field("created_at", .datetime)
      .unique(on: "workspace_id", "sequence")
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeEventLog.schema).delete()
  }
}

private func seedIfNeeded(on db: Database) throws {
  let count = try BridgeWorkspace.query(on: db).count().wait()
  guard count == 0 else { return }

  let seedA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
  let seedB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

  let workspaces = [
    BridgeWorkspace(id: seedA, name: "Operação", connectivity: ConnectivityState.qrRequired.rawValue, unreadTotal: 3, workerState: WorkerState.provisioning.rawValue, qrPayload: "WASPACES-QR-OPERACAO"),
    BridgeWorkspace(id: seedB, name: "Suporte", connectivity: ConnectivityState.connected.rawValue, unreadTotal: 1, workerState: WorkerState.running.rawValue, qrPayload: "WASPACES-QR-SUPORTE")
  ]

  for workspace in workspaces {
    try workspace.create(on: db).wait()
  }

  let conversations = [
    BridgeConversation(id: "op-1", workspaceID: seedA, title: "Cliente 101", lastMessagePreview: "Consegue me atualizar?", unreadCount: 2, status: ConversationStatus.active.rawValue, lastMessageAt: Date()),
    BridgeConversation(id: "sup-1", workspaceID: seedB, title: "Atendimento", lastMessagePreview: "Ticket recebido.", unreadCount: 1, status: ConversationStatus.active.rawValue, lastMessageAt: Date())
  ]

  for conversation in conversations {
    try conversation.create(on: db).wait()
  }

  let messages = [
    BridgeMessage(id: "msg-op-1", workspaceID: seedA, conversationID: "op-1", direction: MessageDirection.incoming.rawValue, authorDisplayName: "Cliente 101", contentText: "Consegue me atualizar?", sentAt: Date(), delivery: DeliveryStatus.read.rawValue),
    BridgeMessage(id: "msg-sup-1", workspaceID: seedB, conversationID: "sup-1", direction: MessageDirection.incoming.rawValue, authorDisplayName: "Atendimento", contentText: "Ticket recebido.", sentAt: Date(), delivery: DeliveryStatus.read.rawValue)
  ]

  for message in messages {
    try message.create(on: db).wait()
  }
}

private struct SyncRequest: Content {
  let cursor: SyncCursor?
}

func routes(_ app: Application) throws {
  app.get("v1", "workspaces") { req async throws -> Response in
    let workspaces = try await BridgeWorkspace.query(on: req.db).all()
    return try jsonResponse(workspaces.map { $0.toContract() })
  }

  app.post("v1", "workspaces", ":workspaceID", "sync") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }

    let syncRequest = try? req.content.decode(SyncRequest.self)
    if let cursor = syncRequest?.cursor {
      let delta = try await makeDeltaPayload(workspaceID: workspaceID, cursor: cursor, db: req.db)
      let envelope = BridgeEnvelope(eventID: delta.cursor.lastEventID ?? UUID().uuidString, emittedAt: Date(), payload: delta)
      return try jsonResponse(envelope)
    }

    let snapshot = try await makeSnapshotPayload(workspaceID: workspaceID, db: req.db)
    let envelope = BridgeEnvelope(eventID: snapshot.cursor.lastEventID ?? UUID().uuidString, emittedAt: Date(), payload: snapshot)
    return try jsonResponse(envelope)
  }

  app.get("v1", "workspaces", ":workspaceID", "events") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }

    let latestCursor = try await currentCursor(workspaceID: workspaceID, db: req.db)
    let previous = SyncCursor(workspaceID: workspaceID, sequence: max(0, latestCursor.sequence - 10), lastEventID: nil, checkpointAt: latestCursor.checkpointAt)
    let delta = try await makeDeltaPayload(workspaceID: workspaceID, cursor: previous, db: req.db)
    let envelope = BridgeEnvelope(eventID: delta.cursor.lastEventID ?? UUID().uuidString, emittedAt: Date(), payload: delta)

    let payloadData = try BridgeCodec.makeEncoder().encode(envelope)
    let payloadString = String(decoding: payloadData, as: UTF8.self)
    let sseBody = "event: delta\ndata: \(payloadString)\n\n"

    var headers = HTTPHeaders()
    headers.contentType = .init(type: "text", subType: "event-stream")
    headers.add(name: .cacheControl, value: "no-cache")

    return Response(status: .ok, headers: headers, body: .init(string: sseBody))
  }

  app.get("v1", "workspaces", ":workspaceID", "qr") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }
    guard let workspace = try await BridgeWorkspace.find(workspaceID, on: req.db) else {
      throw Abort(.notFound)
    }

    let state: QRConnectionState = workspace.connectivity == ConnectivityState.connected.rawValue ? .linked : .pending
    let payload = WorkspaceQRState(
      workspaceID: workspaceID,
      state: state,
      qrPayload: workspace.qrPayload,
      expiresAt: Date().addingTimeInterval(75)
    )
    let envelope = BridgeEnvelope(eventID: "qr-\(workspaceID.uuidString)", emittedAt: Date(), payload: payload)
    return try jsonResponse(envelope)
  }

  app.post("v1", "workspaces", ":workspaceID", "messages", "send") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }

    let command = try req.content.decode(SendMessageCommand.self)

    if let existing = try await BridgeCommandDedupe.query(on: req.db)
      .filter(\.$workspaceID == workspaceID)
      .filter(\.$clientMessageID == command.clientMessageID)
      .first() {
      let replay = SendMessageResult(
        clientMessageID: existing.clientMessageID,
        providerMessageID: existing.providerMessageID,
        accepted: existing.accepted,
        failureReason: existing.failureReason,
        processedAt: existing.processedAt ?? Date()
      )
      return try jsonResponse(replay)
    }

    let normalized = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let accepted = !normalized.lowercased().contains("falha")
    let providerID = accepted ? "provider-\(command.clientMessageID.uuidString)" : nil
    let failure = accepted ? nil : "mock_send_failure"
    let processedAt = Date()

    let result = SendMessageResult(
      clientMessageID: command.clientMessageID,
      providerMessageID: providerID,
      accepted: accepted,
      failureReason: failure,
      processedAt: processedAt
    )

    let dedupe = BridgeCommandDedupe(
      workspaceID: workspaceID,
      clientMessageID: command.clientMessageID,
      providerMessageID: providerID,
      accepted: accepted,
      failureReason: failure,
      processedAt: processedAt
    )
    try await dedupe.save(on: req.db)

    let outgoingMessage = ThreadMessage(
      id: command.clientMessageID.uuidString,
      workspaceID: workspaceID,
      conversationID: command.conversationID,
      direction: .outgoing,
      authorDisplayName: "Você",
      content: .text(normalized),
      sentAt: processedAt,
      delivery: accepted ? .sent : .failed
    )

    let messageModel = BridgeMessage(
      id: outgoingMessage.id,
      workspaceID: workspaceID,
      conversationID: outgoingMessage.conversationID,
      direction: outgoingMessage.direction.rawValue,
      authorDisplayName: outgoingMessage.authorDisplayName,
      contentText: normalized,
      sentAt: processedAt,
      delivery: outgoingMessage.delivery.rawValue
    )
    try await messageModel.save(on: req.db)

    if let conversation = try await BridgeConversation.find(command.conversationID, on: req.db) {
      conversation.lastMessagePreview = normalized
      conversation.lastMessageAt = processedAt
      try await conversation.save(on: req.db)
    }

    try await appendEvent(workspaceID: workspaceID, event: .messageUpserted(outgoingMessage), on: req.db)
    try await appendEvent(workspaceID: workspaceID, event: .messageStatusChanged(messageID: outgoingMessage.id, status: outgoingMessage.delivery), on: req.db)

    return try jsonResponse(result)
  }
}

private func makeSnapshotPayload(workspaceID: UUID, db: Database) async throws -> SyncSnapshotPayload {
  guard let workspace = try await BridgeWorkspace.find(workspaceID, on: db) else {
    throw Abort(.notFound)
  }
  let conversations = try await BridgeConversation.query(on: db)
    .filter(\.$workspaceID == workspaceID)
    .all()
  let messages = try await BridgeMessage.query(on: db)
    .filter(\.$workspaceID == workspaceID)
    .all()

  let conversationContracts = conversations.map { $0.toContract() }
  let groupedMessages = Dictionary(grouping: messages.map { $0.toContract() }, by: \ .conversationID)
  let cursor = try await currentCursor(workspaceID: workspaceID, db: db)

  return SyncSnapshotPayload(
    workspace: workspace.toContract(),
    conversations: conversationContracts,
    messages: groupedMessages,
    cursor: cursor
  )
}

private func makeDeltaPayload(workspaceID: UUID, cursor: SyncCursor, db: Database) async throws -> SyncDeltaPayload {
  let logs = try await BridgeEventLog.query(on: db)
    .filter(\.$workspaceID == workspaceID)
    .filter(\.$sequence > cursor.sequence)
    .sort(\.$sequence, .ascending)
    .all()

  let decoder = BridgeCodec.makeDecoder()
  let events = try logs.compactMap { log -> RealtimeEvent in
    guard let data = log.eventJSON.data(using: .utf8) else {
      throw Abort(.internalServerError)
    }
    return try decoder.decode(RealtimeEvent.self, from: data)
  }

  let latestSequence = logs.last?.sequence ?? cursor.sequence
  let latestEventID = logs.last?.eventID ?? cursor.lastEventID

  return SyncDeltaPayload(
    workspaceID: workspaceID,
    events: events,
    cursor: SyncCursor(
      workspaceID: workspaceID,
      sequence: latestSequence,
      lastEventID: latestEventID,
      checkpointAt: Date()
    )
  )
}

private func currentCursor(workspaceID: UUID, db: Database) async throws -> SyncCursor {
  let latest = try await BridgeEventLog.query(on: db)
    .filter(\.$workspaceID == workspaceID)
    .sort(\.$sequence, .descending)
    .first()

  return SyncCursor(
    workspaceID: workspaceID,
    sequence: latest?.sequence ?? 0,
    lastEventID: latest?.eventID,
    checkpointAt: latest?.createdAt ?? Date()
  )
}

private func appendEvent(workspaceID: UUID, event: RealtimeEvent, on db: Database) async throws {
  let latestSequence = try await BridgeEventLog.query(on: db)
    .filter(\.$workspaceID == workspaceID)
    .sort(\.$sequence, .descending)
    .first()?.sequence ?? 0

  let sequence = latestSequence + 1
  let eventID = "evt-\(workspaceID.uuidString)-\(sequence)"
  let data = try BridgeCodec.makeEncoder().encode(event)
  let json = String(decoding: data, as: UTF8.self)

  let log = BridgeEventLog(sequence: sequence, workspaceID: workspaceID, eventID: eventID, eventJSON: json, createdAt: Date())
  try await log.save(on: db)
}

private func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
  let data = try BridgeCodec.makeEncoder().encode(value)
  var headers = HTTPHeaders()
  headers.contentType = .json
  return Response(status: .ok, headers: headers, body: .init(data: data))
}

private extension BridgeWorkspace {
  func toContract() -> WorkspaceSnapshot {
    WorkspaceSnapshot(
      id: id ?? UUID(),
      name: name,
      connectivity: ConnectivityState(rawValue: connectivity) ?? .disconnected,
      unreadTotal: unreadTotal,
      lastSyncAt: updatedAt,
      workerState: WorkerState(rawValue: workerState) ?? .retrying
    )
  }
}

private extension BridgeConversation {
  func toContract() -> ConversationSummary {
    ConversationSummary(
      id: id ?? UUID().uuidString,
      workspaceID: workspaceID,
      title: title,
      avatarURL: nil,
      lastMessagePreview: lastMessagePreview,
      lastMessageAt: lastMessageAt,
      unreadCount: unreadCount,
      pinRank: nil,
      muteUntil: nil,
      status: ConversationStatus(rawValue: status) ?? .active
    )
  }
}

private extension BridgeMessage {
  func toContract() -> ThreadMessage {
    ThreadMessage(
      id: id ?? UUID().uuidString,
      workspaceID: workspaceID,
      conversationID: conversationID,
      direction: MessageDirection(rawValue: direction) ?? .incoming,
      authorDisplayName: authorDisplayName,
      content: .text(contentText),
      sentAt: sentAt ?? Date(),
      delivery: DeliveryStatus(rawValue: delivery) ?? .pending
    )
  }
}
