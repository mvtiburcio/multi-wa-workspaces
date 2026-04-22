import Foundation
import OSLog
import WorkspaceApplicationServices
import WorkspaceBridgeClient
import WorkspaceBridgeContracts

@MainActor
protocol WorkspaceBridgeRealtimeServicing: AnyObject {
  func start(workspaceIDs: [UUID]) async throws
  func update(workspaceIDs: [UUID]) async
  func stop()
}

enum WorkspaceBridgeRuntimeError: Error {
  case eventStreamEnded
}

@MainActor
final class WorkspaceBridgeRealtimeService: WorkspaceBridgeRealtimeServicing {
  private let client: SessionBridgeClient
  private weak var manager: WorkspaceManager?
  private let logger: Logger

  private var streamTasks: [UUID: Task<Void, Never>] = [:]
  private var conversationUnreadByWorkspace: [UUID: [String: Int]] = [:]

  init(
    client: SessionBridgeClient,
    manager: WorkspaceManager,
    logger: Logger = Logger(subsystem: "com.waspaces.app", category: "bridge_realtime")
  ) {
    self.client = client
    self.manager = manager
    self.logger = logger
  }

  func start(workspaceIDs: [UUID]) async throws {
    _ = try await client.fetchWorkspaceList()
    await update(workspaceIDs: workspaceIDs)
  }

  func update(workspaceIDs: [UUID]) async {
    let requestedIDs = Set(workspaceIDs)

    for (workspaceID, task) in streamTasks where !requestedIDs.contains(workspaceID) {
      task.cancel()
      streamTasks.removeValue(forKey: workspaceID)
      conversationUnreadByWorkspace.removeValue(forKey: workspaceID)
    }

    for workspaceID in requestedIDs where streamTasks[workspaceID] == nil {
      streamTasks[workspaceID] = Task { @MainActor [weak self] in
        await self?.runStreamLoop(for: workspaceID)
      }
    }
  }

  func stop() {
    for task in streamTasks.values {
      task.cancel()
    }
    streamTasks.removeAll()
    conversationUnreadByWorkspace.removeAll()
  }

  private func runStreamLoop(for workspaceID: UUID) async {
    var retryDelayNS: UInt64 = 1_000_000_000

    while !Task.isCancelled {
      do {
        try await hydrateAndConsume(workspaceID: workspaceID)
        retryDelayNS = 1_000_000_000
      } catch {
        logger.warning(
          "workspace_id=\(workspaceID.uuidString, privacy: .public) event=bridge_stream_error duration_ms=0 result=\(String(describing: error), privacy: .public)"
        )

        try? await Task.sleep(nanoseconds: retryDelayNS)
        retryDelayNS = min(retryDelayNS * 2, 30_000_000_000)
      }
    }
  }

  private func hydrateAndConsume(workspaceID: UUID) async throws {
    let snapshotEnvelope = try await client.fetchSnapshot(for: workspaceID)
    applySnapshot(snapshotEnvelope.payload)

    for try await envelope in client.events(for: workspaceID) {
      applyDelta(envelope.payload)
    }

    throw WorkspaceBridgeRuntimeError.eventStreamEnded
  }

  private func applySnapshot(_ payload: SyncSnapshotPayload) {
    manager?.applyBridgeWorkspaceSnapshot(payload.workspace)

    var conversationUnread: [String: Int] = [:]
    for conversation in payload.conversations {
      conversationUnread[conversation.id] = conversation.unreadCount
    }

    conversationUnreadByWorkspace[payload.workspace.id] = conversationUnread
    manager?.applyBridgeUnreadCount(workspaceID: payload.workspace.id, unreadCount: totalUnread(workspaceID: payload.workspace.id))
  }

  private func applyDelta(_ payload: SyncDeltaPayload) {
    for event in payload.events {
      switch event {
      case .workspaceUpdated(let snapshot):
        manager?.applyBridgeWorkspaceSnapshot(snapshot)

      case .conversationUpserted(let conversation):
        var map = conversationUnreadByWorkspace[conversation.workspaceID] ?? [:]
        map[conversation.id] = conversation.unreadCount
        conversationUnreadByWorkspace[conversation.workspaceID] = map
        manager?.applyBridgeUnreadCount(
          workspaceID: conversation.workspaceID,
          unreadCount: totalUnread(workspaceID: conversation.workspaceID)
        )

      case .messageUpserted:
        continue

      case .messageStatusChanged:
        continue

      case .syncCheckpoint:
        continue
      }
    }
  }

  private func totalUnread(workspaceID: UUID) -> Int {
    let map = conversationUnreadByWorkspace[workspaceID] ?? [:]
    return map.values.reduce(0, +)
  }
}
