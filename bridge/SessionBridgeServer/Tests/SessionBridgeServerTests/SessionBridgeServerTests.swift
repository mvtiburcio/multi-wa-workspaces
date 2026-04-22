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
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let envelope = try BridgeCodec.makeDecoder().decode(BridgeErrorEnvelope.self, from: data)
      XCTAssertEqual(envelope.code, .unauthorized)
    }
  }

  func testSyncAndSendAndQRFlow() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configure(app)
    let token = ProcessInfo.processInfo.environment["WASPACES_BRIDGE_API_TOKEN"] ?? "dev-local-token"

    var workspaceID: UUID?
    let create = CreateWorkspaceRequest(name: "Workspace Teste")
    try app.test(
      .POST,
      "/v1/workspaces",
      headers: [
        "Authorization": "Bearer \(token)",
        "Content-Type": "application/json"
      ],
      beforeRequest: { req in
        req.body = ByteBuffer(data: try BridgeCodec.makeEncoder().encode(create))
      }
    ) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let workspace = try BridgeCodec.makeDecoder().decode(WorkspaceSnapshot.self, from: data)
      workspaceID = workspace.id
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
      conversationID: "conv-test",
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

    try app.test(.GET, "/v1/workspaces/\(id.uuidString)/updates", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      _ = try BridgeCodec.makeDecoder().decode([UpdateItem].self, from: data)
    }

    try app.test(.GET, "/v1/workspaces/\(id.uuidString)/calls", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      _ = try BridgeCodec.makeDecoder().decode([CallItem].self, from: data)
    }

    try app.test(.GET, "/v1/workspaces/\(id.uuidString)/notifications", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let notifications = try BridgeCodec.makeDecoder().decode([NotificationQueueItem].self, from: data)
      XCTAssertFalse(notifications.isEmpty)
    }
  }

  func testCreateWorkspaceEndpoint() throws {
    let app = Application(.testing)
    defer { app.shutdown() }

    try configure(app)
    let token = ProcessInfo.processInfo.environment["WASPACES_BRIDGE_API_TOKEN"] ?? "dev-local-token"

    let request = CreateWorkspaceRequest(name: "Novo Workspace")
    var createdWorkspace: WorkspaceSnapshot?

    try app.test(
      .POST,
      "/v1/workspaces",
      headers: [
        "Authorization": "Bearer \(token)",
        "Content-Type": "application/json"
      ],
      beforeRequest: { req in
        req.body = ByteBuffer(data: try BridgeCodec.makeEncoder().encode(request))
      }
    ) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let workspace = try BridgeCodec.makeDecoder().decode(WorkspaceSnapshot.self, from: data)
      XCTAssertEqual(workspace.name, "Novo Workspace")
      XCTAssertEqual(workspace.connectivity, .qrRequired)
      createdWorkspace = workspace
    }

    let id = try XCTUnwrap(createdWorkspace?.id)

    try app.test(.POST, "/v1/workspaces/\(id.uuidString)/sync", headers: ["Authorization": "Bearer \(token)"]) { response in
      XCTAssertEqual(response.status, .ok)
      var buffer = response.body
      let data = buffer.readData(length: buffer.readableBytes) ?? Data()
      let envelope = try BridgeCodec.makeDecoder().decode(BridgeEnvelope<SyncSnapshotPayload>.self, from: data)
      XCTAssertEqual(envelope.payload.workspace.id, id)
    }
  }
}
