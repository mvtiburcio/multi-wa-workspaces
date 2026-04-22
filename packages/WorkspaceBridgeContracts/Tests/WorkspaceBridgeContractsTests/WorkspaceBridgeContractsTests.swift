import Foundation
import Testing
@testable import WorkspaceBridgeContracts

struct WorkspaceBridgeContractsTests {
  @Test
  func syncSnapshotEnvelopeRoundTripUsesSchemaVersionAndFractionalISODate() throws {
    let workspaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let emittedAt = Date(timeIntervalSince1970: 1_713_793_022.123)
    let messageDate = Date(timeIntervalSince1970: 1_713_793_100.456)
    let cursorDate = Date(timeIntervalSince1970: 1_713_793_130.789)

    let payload = SyncSnapshotPayload(
      workspace: WorkspaceSnapshot(
        id: workspaceID,
        name: "Sales",
        connectivity: .connected,
        unreadTotal: 3,
        lastSyncAt: emittedAt,
        workerState: .running
      ),
      conversations: [
        ConversationSummary(
          id: "conv-1",
          workspaceID: workspaceID,
          title: "Cliente A",
          avatarURL: URL(string: "https://example.com/avatar.png"),
          lastMessagePreview: "ok",
          lastMessageAt: emittedAt,
          unreadCount: 2,
          pinRank: nil,
          muteUntil: nil,
          status: .active
        )
      ],
      messages: [
        "conv-1": [
          ThreadMessage(
            id: "msg-1",
            workspaceID: workspaceID,
            conversationID: "conv-1",
            direction: .incoming,
            authorDisplayName: "Cliente",
            content: .text("Olá"),
            sentAt: messageDate,
            delivery: .read
          )
        ]
      ],
      cursor: SyncCursor(workspaceID: workspaceID, sequence: 10, lastEventID: "evt-10", checkpointAt: cursorDate)
    )

    let envelope = BridgeEnvelope(
      schemaVersion: 1,
      eventID: "evt-sync-10",
      emittedAt: emittedAt,
      payload: payload
    )

    let encoder = BridgeCodec.makeEncoder()
    let decoder = BridgeCodec.makeDecoder()

    let data = try encoder.encode(envelope)
    let rawJSON = String(decoding: data, as: UTF8.self)

    #expect(rawJSON.contains("\"schemaVersion\":1"))
    #expect(rawJSON.contains("2024-04-22T"))
    #expect(rawJSON.contains(".123Z") || rawJSON.contains(".456Z") || rawJSON.contains(".789Z"))

    let decoded = try decoder.decode(BridgeEnvelope<SyncSnapshotPayload>.self, from: data)
    #expect(decoded == envelope)
  }

  @Test
  func realtimeEnvelopeRoundTripMaintainsEnumPayload() throws {
    let workspaceID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let now = Date(timeIntervalSince1970: 1_713_794_000.111)

    let event = RealtimeEvent.messageStatusChanged(messageID: "msg-1", status: .delivered)
    let payload = SyncDeltaPayload(
      workspaceID: workspaceID,
      events: [event],
      cursor: SyncCursor(workspaceID: workspaceID, sequence: 11, lastEventID: "evt-11", checkpointAt: now)
    )

    let envelope = BridgeEnvelope(schemaVersion: 1, eventID: "evt-11", emittedAt: now, payload: payload)
    let encoded = try BridgeCodec.makeEncoder().encode(envelope)
    let decoded = try BridgeCodec.makeDecoder().decode(BridgeEnvelope<SyncDeltaPayload>.self, from: encoded)

    #expect(decoded == envelope)
    #expect(decoded.schemaVersion == BridgeEnvelopeDefaults.schemaVersion)
  }

  @Test
  func bridgeErrorEnvelopeIncludesRetryHints() throws {
    let value = BridgeErrorEnvelope(
      code: .rateLimited,
      message: "Too many requests",
      retryAfterMilliseconds: 1500
    )

    let encoded = try BridgeCodec.makeEncoder().encode(value)
    let decoded = try BridgeCodec.makeDecoder().decode(BridgeErrorEnvelope.self, from: encoded)

    #expect(decoded == value)
    #expect(decoded.schemaVersion == 1)
  }

  @Test
  func decoderAcceptsISO8601WithoutFractionalSeconds() throws {
    let payload = #"{"schemaVersion":1,"eventID":"evt-plain-seconds","emittedAt":"2026-04-22T12:00:00Z","payload":{"workspaceID":"11111111-1111-1111-1111-111111111111","events":[],"cursor":{"workspaceID":"11111111-1111-1111-1111-111111111111","sequence":1,"lastEventID":"evt-plain-seconds","checkpointAt":"2026-04-22T12:00:00Z"}}}"#
    let decoded = try BridgeCodec.makeDecoder().decode(BridgeEnvelope<SyncDeltaPayload>.self, from: Data(payload.utf8))
    let expected = ISO8601DateFormatter().date(from: "2026-04-22T12:00:00Z")
    #expect(decoded.eventID == "evt-plain-seconds")
    #expect(decoded.emittedAt == expected)
  }
}
