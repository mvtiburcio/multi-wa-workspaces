import XCTest
import XCTVapor
@testable import SessionBridgeServer
import WorkspaceBridgeContracts

final class SessionBridgeServerTests: XCTestCase {
  func testUnauthorizedWhenBearerMissing() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configure(app)

    try app.test(.GET, "/v1/workspaces") { response in
      XCTAssertEqual(response.status, .unauthorized)
    }
  }

  func testSyncAndSendAndQRFlow() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configure(app)
    let token = ProcessInfo.processInfo.environment["WASPACES_BRIDGE_API_TOKEN"] ?? "dev-local-token"

    var workspaceID: UUID?
    try app.test(.GET, "/v1/workspaces", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let list = try BridgeCodec.makeDecoder().decode([WorkspaceSnapshot].self, from: data)
      XCTAssertFalse(list.isEmpty)
      workspaceID = list.first?.id
    }

    let id = try XCTUnwrap(workspaceID)

    try app.test(.POST, "/v1/workspaces/\(id.uuidString)/sync", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      _ = try BridgeCodec.makeDecoder().decode(BridgeEnvelope<SyncSnapshotPayload>.self, from: data)
    }

    let command = SendMessageCommand(
      workspaceID: id,
      conversationID: "op-1",
      clientMessageID: UUID(),
      text: "mensagem teste",
      requestedAt: Date()
    )

    try app.test(
      .POST,
      "/v1/workspaces/\(id.uuidString)/messages/send",
      headers: [
        "Authorization": "Bearer \(token)",
        "Content-Type": "application/json"
      ],
      beforeRequest: { req in
        req.body = ByteBuffer(data: try BridgeCodec.makeEncoder().encode(command))
      }
    ) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let result = try BridgeCodec.makeDecoder().decode(SendMessageResult.self, from: data)
      XCTAssertTrue(result.accepted)
    }

    try app.test(.GET, "/v1/workspaces/\(id.uuidString)/events", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      XCTAssertEqual(response.headers.contentType?.description, "text/event-stream")
      XCTAssertTrue(response.body.string.contains("data:"))
    }

    try app.test(.GET, "/v1/workspaces/\(id.uuidString)/qr", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      _ = try BridgeCodec.makeDecoder().decode(BridgeEnvelope<WorkspaceQRState>.self, from: data)
    }
  }
}
