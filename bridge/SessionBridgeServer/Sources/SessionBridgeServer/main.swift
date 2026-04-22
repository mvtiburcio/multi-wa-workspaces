import Fluent
import FluentSQLiteDriver
import Foundation
import Vapor
import WorkspaceBridgeContracts

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = try await Application.make(env)
try configure(app)
try await app.execute()
try await app.asyncShutdown()

func configure(_ app: Application) throws {
  let runtime = BridgeRuntimeConfiguration.fromEnvironment()
  let databasePath = Environment.get("WASPACES_BRIDGE_DB_PATH") ?? "bridge-session.sqlite"
  app.databases.use(.sqlite(.file(databasePath)), as: .sqlite)

  app.migrations.add(CreateWorkspaceMigration())
  app.migrations.add(CreateConversationMigration())
  app.migrations.add(CreateMessageMigration())
  app.migrations.add(CreateCommandDedupeMigration())
  app.migrations.add(CreateEventLogMigration())
  app.migrations.add(CreateUpdateItemMigration())
  app.migrations.add(CreateCallItemMigration())
  app.migrations.add(CreateNotificationQueueMigration())

  try app.autoMigrate().wait()
  try seedIfNeeded(on: app.db, mode: runtime.seedMode)

  app.middleware.use(BridgeErrorMiddleware())
  app.middleware.use(BridgeAuthMiddleware(token: Environment.get("WASPACES_BRIDGE_API_TOKEN") ?? "dev-local-token"))
  try routes(app, runtime: runtime)
}

private struct BridgeAuthMiddleware: AsyncMiddleware {
  let token: String

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    let publicPaths: Set<String> = ["/healthz", "/readyz"]
    if publicPaths.contains(request.url.path) {
      return try await next.respond(to: request)
    }
    guard let authorization = request.headers.bearerAuthorization?.token, authorization == token else {
      throw Abort(.unauthorized, reason: "invalid bearer token")
    }
    return try await next.respond(to: request)
  }
}

private struct BridgeErrorMiddleware: AsyncMiddleware {
  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    do {
      return try await next.respond(to: request)
    } catch let abort as Abort {
      let error = BridgeErrorEnvelope(
        code: mapErrorCode(from: abort.status),
        message: abort.reason,
        retryAfterMilliseconds: retryAfter(for: abort.status)
      )
      return makeErrorResponse(status: abort.status, payload: error)
    } catch {
      request.logger.error("bridge_unhandled_error path=\(request.url.path) error=\(String(describing: error))")
      let payload = BridgeErrorEnvelope(
        code: .internalError,
        message: "internal bridge error",
        retryAfterMilliseconds: 1000
      )
      return makeErrorResponse(status: .internalServerError, payload: payload)
    }
  }

  private func mapErrorCode(from status: HTTPResponseStatus) -> BridgeErrorCode {
    switch status {
    case .unauthorized:
      return .unauthorized
    case .notFound:
      return .workspaceNotFound
    case .tooManyRequests:
      return .rateLimited
    case .serviceUnavailable, .gatewayTimeout, .requestTimeout:
      return .transientNetwork
    default:
      return .internalError
    }
  }

  private func retryAfter(for status: HTTPResponseStatus) -> Int? {
    switch status {
    case .tooManyRequests:
      return 1200
    case .serviceUnavailable, .gatewayTimeout, .requestTimeout:
      return 1000
    default:
      return nil
    }
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

final class BridgeUpdateItemModel: Model, @unchecked Sendable {
  static let schema = "bridge_update_items"

  @ID(custom: "id", generatedBy: .user) var id: String?
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "title") var title: String
  @Field(key: "subtitle") var subtitle: String
  @Field(key: "timestamp") var timestamp: Date
  @Field(key: "kind") var kind: String
  @Field(key: "unread") var unread: Bool

  init() {}

  init(id: String, workspaceID: UUID, title: String, subtitle: String, timestamp: Date, kind: String, unread: Bool) {
    self.id = id
    self.workspaceID = workspaceID
    self.title = title
    self.subtitle = subtitle
    self.timestamp = timestamp
    self.kind = kind
    self.unread = unread
  }
}

final class BridgeCallItemModel: Model, @unchecked Sendable {
  static let schema = "bridge_call_items"

  @ID(custom: "id", generatedBy: .user) var id: String?
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "contact_name") var contactName: String
  @Field(key: "occurred_at") var occurredAt: Date
  @Field(key: "duration_seconds") var durationSeconds: Int
  @Field(key: "direction") var direction: String

  init() {}

  init(id: String, workspaceID: UUID, contactName: String, occurredAt: Date, durationSeconds: Int, direction: String) {
    self.id = id
    self.workspaceID = workspaceID
    self.contactName = contactName
    self.occurredAt = occurredAt
    self.durationSeconds = durationSeconds
    self.direction = direction
  }
}

final class BridgeNotificationQueueModel: Model, @unchecked Sendable {
  static let schema = "bridge_notification_queue"

  @ID(key: .id) var id: UUID?
  @Field(key: "workspace_id") var workspaceID: UUID
  @Field(key: "event") var event: String
  @Field(key: "payload_json") var payloadJSON: String
  @Field(key: "status") var status: String
  @Timestamp(key: "created_at", on: .none) var createdAt: Date?
  @Timestamp(key: "processed_at", on: .none) var processedAt: Date?

  init() {}

  init(
    workspaceID: UUID,
    event: String,
    payloadJSON: String,
    status: String,
    createdAt: Date,
    processedAt: Date?
  ) {
    self.workspaceID = workspaceID
    self.event = event
    self.payloadJSON = payloadJSON
    self.status = status
    self.createdAt = createdAt
    self.processedAt = processedAt
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

struct CreateUpdateItemMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeUpdateItemModel.schema)
      .field("id", .string, .identifier(auto: false))
      .field("workspace_id", .uuid, .required)
      .field("title", .string, .required)
      .field("subtitle", .string, .required)
      .field("timestamp", .datetime, .required)
      .field("kind", .string, .required)
      .field("unread", .bool, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeUpdateItemModel.schema).delete()
  }
}

struct CreateCallItemMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeCallItemModel.schema)
      .field("id", .string, .identifier(auto: false))
      .field("workspace_id", .uuid, .required)
      .field("contact_name", .string, .required)
      .field("occurred_at", .datetime, .required)
      .field("duration_seconds", .int, .required)
      .field("direction", .string, .required)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeCallItemModel.schema).delete()
  }
}

struct CreateNotificationQueueMigration: AsyncMigration {
  func prepare(on database: Database) async throws {
    try await database.schema(BridgeNotificationQueueModel.schema)
      .id()
      .field("workspace_id", .uuid, .required)
      .field("event", .string, .required)
      .field("payload_json", .string, .required)
      .field("status", .string, .required)
      .field("created_at", .datetime)
      .field("processed_at", .datetime)
      .create()
  }

  func revert(on database: Database) async throws {
    try await database.schema(BridgeNotificationQueueModel.schema).delete()
  }
}

private func seedIfNeeded(on db: Database, mode: BridgeRuntimeConfiguration.SeedMode) throws {
  guard mode == .sample else {
    return
  }

  let count = try BridgeWorkspace.query(on: db).count().wait()
  let seedA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
  let seedB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

  guard count == 0 else {
    let updateCount = try BridgeUpdateItemModel.query(on: db).count().wait()
    if updateCount == 0 {
      let updates = [
        BridgeUpdateItemModel(
          id: "upd-op-1",
          workspaceID: seedA,
          title: "Equipe Operação",
          subtitle: "Status atualizado",
          timestamp: Date(),
          kind: "status",
          unread: true
        ),
        BridgeUpdateItemModel(
          id: "upd-sup-1",
          workspaceID: seedB,
          title: "Canal Suporte",
          subtitle: "Resumo do plantão",
          timestamp: Date().addingTimeInterval(-1800),
          kind: "channel",
          unread: false
        )
      ]
      for update in updates {
        try update.save(on: db).wait()
      }
    }

    let callCount = try BridgeCallItemModel.query(on: db).count().wait()
    if callCount == 0 {
      let calls = [
        BridgeCallItemModel(
          id: "call-op-1",
          workspaceID: seedA,
          contactName: "Cliente 101",
          occurredAt: Date().addingTimeInterval(-900),
          durationSeconds: 248,
          direction: "outgoing"
        ),
        BridgeCallItemModel(
          id: "call-sup-1",
          workspaceID: seedB,
          contactName: "Suporte N2",
          occurredAt: Date().addingTimeInterval(-3600),
          durationSeconds: 0,
          direction: "missed"
        )
      ]
      for call in calls {
        try call.save(on: db).wait()
      }
    }

    return
  }

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

  let updates = [
    BridgeUpdateItemModel(
      id: "upd-op-1",
      workspaceID: seedA,
      title: "Equipe Operação",
      subtitle: "Status atualizado",
      timestamp: Date(),
      kind: "status",
      unread: true
    ),
    BridgeUpdateItemModel(
      id: "upd-sup-1",
      workspaceID: seedB,
      title: "Canal Suporte",
      subtitle: "Resumo do plantão",
      timestamp: Date().addingTimeInterval(-1800),
      kind: "channel",
      unread: false
    )
  ]

  for update in updates {
    try update.create(on: db).wait()
  }

  let calls = [
    BridgeCallItemModel(
      id: "call-op-1",
      workspaceID: seedA,
      contactName: "Cliente 101",
      occurredAt: Date().addingTimeInterval(-900),
      durationSeconds: 248,
      direction: "outgoing"
    ),
    BridgeCallItemModel(
      id: "call-sup-1",
      workspaceID: seedB,
      contactName: "Suporte N2",
      occurredAt: Date().addingTimeInterval(-3600),
      durationSeconds: 0,
      direction: "missed"
    )
  ]

  for call in calls {
    try call.create(on: db).wait()
  }
}

private struct SyncRequest: Content {
  let cursor: SyncCursor?
}

private struct BridgeHealthPayload: Hashable, Codable, Sendable {
  let status: String
  let service: String
  let checkedAt: Date
}

func routes(_ app: Application, runtime: BridgeRuntimeConfiguration) throws {
  app.get("healthz") { _ async throws -> Response in
    try jsonResponse(
      BridgeHealthPayload(
        status: "ok",
        service: "SessionBridgeServer",
        checkedAt: Date()
      )
    )
  }

  app.get("readyz") { req async throws -> Response in
    _ = try await BridgeWorkspace.query(on: req.db).count()
    return try jsonResponse(
      BridgeHealthPayload(
        status: "ready",
        service: "SessionBridgeServer",
        checkedAt: Date()
      )
    )
  }

  app.get("v1", "workspaces") { req async throws -> Response in
    let workspaces = try await BridgeWorkspace.query(on: req.db).all()
    return try jsonResponse(workspaces.map { $0.toContract() })
  }

  app.post("v1", "workspaces") { req async throws -> Response in
    let payload = try req.content.decode(CreateWorkspaceRequest.self)
    let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      throw Abort(.badRequest, reason: "workspace name is required")
    }

    let workspaceID = UUID()
    let workspace = BridgeWorkspace(
      id: workspaceID,
      name: name,
      connectivity: ConnectivityState.qrRequired.rawValue,
      unreadTotal: 0,
      workerState: WorkerState.provisioning.rawValue,
      qrPayload: "WASPACES-QR-\(workspaceID.uuidString.prefix(8))"
    )
    try await workspace.create(on: req.db)

    if runtime.seedMode == .sample {
      let seedConversationID = "seed-\(workspaceID.uuidString.prefix(8))"
      let seedConversation = BridgeConversation(
        id: seedConversationID,
        workspaceID: workspaceID,
        title: "Conversa inicial",
        lastMessagePreview: "Workspace criado. Escaneie o QR para conectar.",
        unreadCount: 0,
        status: ConversationStatus.active.rawValue,
        lastMessageAt: Date()
      )
      try await seedConversation.create(on: req.db)
      try await appendEvent(workspaceID: workspaceID, event: .conversationUpserted(seedConversation.toContract()), on: req.db)
    }

    if let waha = runtime.waha {
      do {
        try await waha.ensureSessionExistsAndStarted(workspaceID: workspaceID)
        let status = try await waha.getSessionStatus(workspaceID: workspaceID)
        workspace.connectivity = mapWahaStatusToConnectivity(status).rawValue
        workspace.workerState = mapWahaStatusToWorkerState(status).rawValue
        if let qr = try await waha.fetchQRCodeRaw(workspaceID: workspaceID), !qr.isEmpty {
          workspace.qrPayload = qr
        }
        try await workspace.save(on: req.db)
      } catch {
        req.logger.warning("waha_provision_failed workspace_id=\(workspaceID.uuidString) error=\(String(describing: error))")
      }
    }

    try await appendEvent(workspaceID: workspaceID, event: .workspaceUpdated(workspace.toContract()), on: req.db)
    try await enqueueNotification(
      workspaceID: workspaceID,
      event: "workspace.qr_required",
      payload: [
        "workspace_id": workspaceID.uuidString,
        "workspace_name": name,
        "connectivity": ConnectivityState.qrRequired.rawValue
      ],
      on: req.db
    )

    return try jsonResponse(workspace.toContract())
  }

  app.post("v1", "workspaces", ":workspaceID", "sync") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }

    if let waha = runtime.waha {
      do {
        try await refreshWorkspaceFromWaha(workspaceID: workspaceID, db: req.db, waha: waha)
      } catch {
        req.logger.warning("waha_sync_refresh_failed workspace_id=\(workspaceID.uuidString) error=\(String(describing: error))")
      }
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

    if let waha = runtime.waha {
      do {
        try await waha.ensureSessionExistsAndStarted(workspaceID: workspaceID)
        let status = try await waha.getSessionStatus(workspaceID: workspaceID)
        workspace.connectivity = mapWahaStatusToConnectivity(status).rawValue
        workspace.workerState = mapWahaStatusToWorkerState(status).rawValue
        if let qr = try await waha.fetchQRCodeRaw(workspaceID: workspaceID), !qr.isEmpty {
          workspace.qrPayload = qr
        }
        try await workspace.save(on: req.db)
      } catch {
        req.logger.warning("waha_qr_failed workspace_id=\(workspaceID.uuidString) error=\(String(describing: error))")
      }
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

  app.get("v1", "workspaces", ":workspaceID", "updates") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }

    let updates = try await BridgeUpdateItemModel.query(on: req.db)
      .filter(\.$workspaceID == workspaceID)
      .sort(\.$timestamp, .descending)
      .all()

    return try jsonResponse(updates.map { $0.toContract() })
  }

  app.get("v1", "workspaces", ":workspaceID", "calls") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }

    let calls = try await BridgeCallItemModel.query(on: req.db)
      .filter(\.$workspaceID == workspaceID)
      .sort(\.$occurredAt, .descending)
      .all()

    return try jsonResponse(calls.map { $0.toContract() })
  }

  app.get("v1", "workspaces", ":workspaceID", "notifications") { req async throws -> Response in
    guard let workspaceID = req.parameters.get("workspaceID", as: UUID.self) else {
      throw Abort(.badRequest)
    }
    let rows = try await BridgeNotificationQueueModel.query(on: req.db)
      .filter(\.$workspaceID == workspaceID)
      .sort(\.$createdAt, .descending)
      .limit(100)
      .all()
    return try jsonResponse(rows.map { $0.toContract() })
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
    var accepted = !normalized.isEmpty
    var providerID: String? = accepted ? "provider-\(command.clientMessageID.uuidString)" : nil
    var failure = accepted ? nil : "empty_message"

    if let waha = runtime.waha {
      do {
        try await waha.ensureSessionExistsAndStarted(workspaceID: workspaceID)
        let external = try await waha.sendText(workspaceID: workspaceID, chatID: command.conversationID, text: normalized)
        accepted = external.accepted
        providerID = external.providerMessageID ?? providerID
        failure = external.failureReason
      } catch {
        accepted = false
        providerID = nil
        failure = "provider_send_failed"
        req.logger.warning("waha_send_failed workspace_id=\(workspaceID.uuidString) chat_id=\(command.conversationID) error=\(String(describing: error))")
      }
    }
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
    } else {
      let createdConversation = BridgeConversation(
        id: command.conversationID,
        workspaceID: workspaceID,
        title: command.conversationID,
        lastMessagePreview: normalized,
        unreadCount: 0,
        status: ConversationStatus.active.rawValue,
        lastMessageAt: processedAt
      )
      try await createdConversation.create(on: req.db)
      try await appendEvent(workspaceID: workspaceID, event: .conversationUpserted(createdConversation.toContract()), on: req.db)
    }

    try await appendEvent(workspaceID: workspaceID, event: .messageUpserted(outgoingMessage), on: req.db)
    try await appendEvent(workspaceID: workspaceID, event: .messageStatusChanged(messageID: outgoingMessage.id, status: outgoingMessage.delivery), on: req.db)
    try await enqueueNotification(
      workspaceID: workspaceID,
      event: "message.send.result",
      payload: [
        "workspace_id": workspaceID.uuidString,
        "conversation_id": command.conversationID,
        "client_message_id": command.clientMessageID.uuidString,
        "accepted": result.accepted.description,
        "provider_message_id": result.providerMessageID ?? "",
        "failure_reason": result.failureReason ?? ""
      ],
      on: req.db
    )

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

private func refreshWorkspaceFromWaha(
  workspaceID: UUID,
  db: Database,
  waha: WahaService
) async throws {
  guard let workspace = try await BridgeWorkspace.find(workspaceID, on: db) else {
    throw Abort(.notFound)
  }

  try await waha.ensureSessionExistsAndStarted(workspaceID: workspaceID)
  let status = try await waha.getSessionStatus(workspaceID: workspaceID)
  workspace.connectivity = mapWahaStatusToConnectivity(status).rawValue
  workspace.workerState = mapWahaStatusToWorkerState(status).rawValue
  if let qrRaw = try await waha.fetchQRCodeRaw(workspaceID: workspaceID), !qrRaw.isEmpty {
    workspace.qrPayload = qrRaw
  }
  try await workspace.save(on: db)

  let overview = try await waha.fetchChatsOverview(workspaceID: workspaceID, limit: 40)
  for item in overview {
    if let existing = try await BridgeConversation.find(item.id, on: db) {
      existing.title = item.name
      existing.lastMessagePreview = item.lastMessageBody
      existing.lastMessageAt = item.lastMessageAt
      existing.unreadCount = item.unreadCount
      existing.status = ConversationStatus.active.rawValue
      try await existing.save(on: db)
    } else {
      let conversation = BridgeConversation(
        id: item.id,
        workspaceID: workspaceID,
        title: item.name,
        lastMessagePreview: item.lastMessageBody,
        unreadCount: item.unreadCount,
        status: ConversationStatus.active.rawValue,
        lastMessageAt: item.lastMessageAt
      )
      try await conversation.create(on: db)
    }
  }

  for item in overview.prefix(12) {
    let messages = try await waha.fetchMessages(workspaceID: workspaceID, chatID: item.id, limit: 40)
    for message in messages {
      if let existing = try await BridgeMessage.find(message.id, on: db) {
        existing.contentText = message.body
        existing.sentAt = message.timestamp
        existing.delivery = mapWahaAckToDelivery(message.ackName).rawValue
        try await existing.save(on: db)
        continue
      }

      let model = BridgeMessage(
        id: message.id,
        workspaceID: workspaceID,
        conversationID: item.id,
        direction: message.fromMe ? MessageDirection.outgoing.rawValue : MessageDirection.incoming.rawValue,
        authorDisplayName: message.fromMe ? "Você" : message.from,
        contentText: message.body,
        sentAt: message.timestamp,
        delivery: mapWahaAckToDelivery(message.ackName).rawValue
      )
      try await model.create(on: db)
    }
  }
}

private func enqueueNotification(
  workspaceID: UUID,
  event: String,
  payload: [String: String],
  on db: Database
) async throws {
  let payloadData = try BridgeCodec.makeEncoder().encode(payload)
  let payloadJSON = String(decoding: payloadData, as: UTF8.self)
  let queueItem = BridgeNotificationQueueModel(
    workspaceID: workspaceID,
    event: event,
    payloadJSON: payloadJSON,
    status: "queued",
    createdAt: Date(),
    processedAt: nil
  )
  try await queueItem.save(on: db)
}

private func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
  let data = try BridgeCodec.makeEncoder().encode(value)
  var headers = HTTPHeaders()
  headers.contentType = .json
  return Response(status: .ok, headers: headers, body: .init(data: data))
}

private func makeErrorResponse(status: HTTPResponseStatus, payload: BridgeErrorEnvelope) -> Response {
  do {
    let data = try BridgeCodec.makeEncoder().encode(payload)
    var headers = HTTPHeaders()
    headers.contentType = .json
    return Response(status: status, headers: headers, body: .init(data: data))
  } catch {
    return Response(status: .internalServerError, body: .init(string: "{\"code\":\"internalError\",\"message\":\"error serialization failed\",\"schemaVersion\":1}"))
  }
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

private extension BridgeUpdateItemModel {
  func toContract() -> UpdateItem {
    UpdateItem(
      id: id ?? UUID().uuidString,
      workspaceID: workspaceID,
      title: title,
      subtitle: subtitle,
      timestamp: timestamp,
      kind: UpdateKind(rawValue: kind) ?? .status,
      unread: unread
    )
  }
}

private extension BridgeCallItemModel {
  func toContract() -> CallItem {
    CallItem(
      id: id ?? UUID().uuidString,
      workspaceID: workspaceID,
      contactName: contactName,
      occurredAt: occurredAt,
      durationSeconds: durationSeconds,
      direction: CallDirection(rawValue: direction) ?? .incoming
    )
  }
}

private extension BridgeNotificationQueueModel {
  func toContract() -> NotificationQueueItem {
    NotificationQueueItem(
      id: id ?? UUID(),
      workspaceID: workspaceID,
      event: event,
      payload: payloadJSON,
      status: status,
      createdAt: createdAt ?? Date(),
      processedAt: processedAt
    )
  }
}
