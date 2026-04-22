import Foundation
import WorkspaceBridgeContracts
import WorkspaceBridgeClient

public enum UpdateKind: String, Hashable, Codable, Sendable {
  case status
  case channel
}

public struct UpdateItem: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let workspaceID: UUID
  public let title: String
  public let subtitle: String
  public let timestamp: Date
  public let kind: UpdateKind
  public let unread: Bool

  public init(
    id: String,
    workspaceID: UUID,
    title: String,
    subtitle: String,
    timestamp: Date,
    kind: UpdateKind,
    unread: Bool
  ) {
    self.id = id
    self.workspaceID = workspaceID
    self.title = title
    self.subtitle = subtitle
    self.timestamp = timestamp
    self.kind = kind
    self.unread = unread
  }
}

public enum CallDirection: String, Hashable, Codable, Sendable {
  case incoming
  case outgoing
  case missed
}

public struct CallItem: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let workspaceID: UUID
  public let contactName: String
  public let occurredAt: Date
  public let durationSeconds: Int
  public let direction: CallDirection

  public init(
    id: String,
    workspaceID: UUID,
    contactName: String,
    occurredAt: Date,
    durationSeconds: Int,
    direction: CallDirection
  ) {
    self.id = id
    self.workspaceID = workspaceID
    self.contactName = contactName
    self.occurredAt = occurredAt
    self.durationSeconds = durationSeconds
    self.direction = direction
  }
}

public protocol WorkspaceProvider: Sendable {
  func fetchWorkspaceList() async throws -> [WorkspaceSnapshot]
  func fetchQRCode(for workspaceID: UUID) async throws -> BridgeEnvelope<WorkspaceQRState>
}

public protocol ChatsProvider: Sendable {
  func fetchSnapshot(for workspaceID: UUID) async throws -> BridgeEnvelope<SyncSnapshotPayload>
  func events(for workspaceID: UUID) -> AsyncThrowingStream<BridgeEnvelope<SyncDeltaPayload>, Error>
  func send(_ command: SendMessageCommand) async throws -> SendMessageResult
}

public protocol UpdatesProvider: Sendable {
  func fetchUpdates(for workspaceID: UUID) async throws -> [UpdateItem]
}

public protocol CallsProvider: Sendable {
  func fetchCalls(for workspaceID: UUID) async throws -> [CallItem]
}

public struct SessionBridgeWorkspaceProvider: WorkspaceProvider {
  private let syncProvider: any SyncProvider
  private let qrProvider: any QRProvider

  public init(syncProvider: any SyncProvider, qrProvider: any QRProvider) {
    self.syncProvider = syncProvider
    self.qrProvider = qrProvider
  }

  public func fetchWorkspaceList() async throws -> [WorkspaceSnapshot] {
    try await syncProvider.fetchWorkspaceList()
  }

  public func fetchQRCode(for workspaceID: UUID) async throws -> BridgeEnvelope<WorkspaceQRState> {
    try await qrProvider.fetchQRCode(for: workspaceID)
  }
}

public struct SessionBridgeChatsProvider: ChatsProvider {
  private let syncProvider: any SyncProvider
  private let realtimeProvider: any RealtimeProvider
  private let sendProvider: any SendMessageProvider

  public init(
    syncProvider: any SyncProvider,
    realtimeProvider: any RealtimeProvider,
    sendProvider: any SendMessageProvider
  ) {
    self.syncProvider = syncProvider
    self.realtimeProvider = realtimeProvider
    self.sendProvider = sendProvider
  }

  public func fetchSnapshot(for workspaceID: UUID) async throws -> BridgeEnvelope<SyncSnapshotPayload> {
    try await syncProvider.fetchSnapshot(for: workspaceID)
  }

  public func events(for workspaceID: UUID) -> AsyncThrowingStream<BridgeEnvelope<SyncDeltaPayload>, Error> {
    realtimeProvider.events(for: workspaceID)
  }

  public func send(_ command: SendMessageCommand) async throws -> SendMessageResult {
    try await sendProvider.send(command)
  }
}

public struct MockUpdatesProvider: UpdatesProvider {
  private let seedDate = Date(timeIntervalSince1970: 1_713_800_300)

  public init() {}

  public func fetchUpdates(for workspaceID: UUID) async throws -> [UpdateItem] {
    [
      UpdateItem(
        id: "upd-\(workspaceID.uuidString.prefix(6))-1",
        workspaceID: workspaceID,
        title: "Equipe \(workspaceLabel(from: workspaceID))",
        subtitle: "Novo status disponível",
        timestamp: seedDate.addingTimeInterval(600),
        kind: .status,
        unread: true
      ),
      UpdateItem(
        id: "upd-\(workspaceID.uuidString.prefix(6))-2",
        workspaceID: workspaceID,
        title: "Canal Operacional",
        subtitle: "Resumo do turno publicado",
        timestamp: seedDate,
        kind: .channel,
        unread: false
      )
    ]
  }

  private func workspaceLabel(from workspaceID: UUID) -> String {
    String(workspaceID.uuidString.prefix(4)).uppercased()
  }
}

public struct MockCallsProvider: CallsProvider {
  private let seedDate = Date(timeIntervalSince1970: 1_713_800_600)

  public init() {}

  public func fetchCalls(for workspaceID: UUID) async throws -> [CallItem] {
    [
      CallItem(
        id: "call-\(workspaceID.uuidString.prefix(6))-1",
        workspaceID: workspaceID,
        contactName: "Cliente VIP",
        occurredAt: seedDate.addingTimeInterval(1800),
        durationSeconds: 420,
        direction: .outgoing
      ),
      CallItem(
        id: "call-\(workspaceID.uuidString.prefix(6))-2",
        workspaceID: workspaceID,
        contactName: "Suporte N2",
        occurredAt: seedDate,
        durationSeconds: 0,
        direction: .missed
      )
    ]
  }
}
