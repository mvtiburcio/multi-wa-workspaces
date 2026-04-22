import Foundation
import WorkspaceBridgeContracts

public protocol SyncProvider: Sendable {
  func fetchWorkspaceList() async throws -> [WorkspaceSnapshot]
  func fetchSnapshot(for workspaceID: UUID) async throws -> BridgeEnvelope<SyncSnapshotPayload>
}

public protocol RealtimeProvider: Sendable {
  func events(for workspaceID: UUID) -> AsyncThrowingStream<BridgeEnvelope<SyncDeltaPayload>, Error>
}

public protocol SendMessageProvider: Sendable {
  func send(_ command: SendMessageCommand) async throws -> SendMessageResult
}

public protocol QRProvider: Sendable {
  func fetchQRCode(for workspaceID: UUID) async throws -> BridgeEnvelope<WorkspaceQRState>
}

public protocol SessionBridgeClient: SyncProvider, RealtimeProvider, SendMessageProvider, QRProvider {}
