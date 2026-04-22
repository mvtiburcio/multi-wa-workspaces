import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import WorkspaceBridgeContracts

struct BridgeRuntimeConfiguration: Sendable {
  enum SeedMode: String, Sendable {
    case none
    case sample
  }

  let seedMode: SeedMode
  let waha: WahaService?

  static func fromEnvironment() -> BridgeRuntimeConfiguration {
    let env = ProcessInfo.processInfo.environment
    let seedRaw = (env["WASPACES_BRIDGE_SEED_MODE"] ?? "none").lowercased()
    let seedMode: SeedMode = seedRaw == "sample" ? .sample : .none

    let enabledRaw = (env["WASPACES_BRIDGE_WAHA_ENABLED"] ?? "0").lowercased()
    let wahaEnabled = enabledRaw == "1" || enabledRaw == "true" || enabledRaw == "yes"

    if wahaEnabled,
       let baseRaw = env["WASPACES_WAHA_BASE_URL"],
       let baseURL = URL(string: baseRaw)
    {
      let apiKey = env["WASPACES_WAHA_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      let sessionPrefix = env["WASPACES_WAHA_SESSION_PREFIX"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      let forceDefaultRaw = (env["WASPACES_WAHA_FORCE_DEFAULT_SESSION"] ?? "0").lowercased()
      let forceDefault = forceDefaultRaw == "1" || forceDefaultRaw == "true" || forceDefaultRaw == "yes"
      return BridgeRuntimeConfiguration(
        seedMode: seedMode,
        waha: WahaService(
          baseURL: baseURL,
          apiKey: (apiKey?.isEmpty == true ? nil : apiKey),
          sessionPrefix: sessionPrefix?.isEmpty == false ? sessionPrefix! : "ws",
          forceDefaultSession: forceDefault
        )
      )
    }

    return BridgeRuntimeConfiguration(seedMode: seedMode, waha: nil)
  }
}

struct WahaChatOverview: Sendable {
  let id: String
  let name: String
  let lastMessageBody: String
  let lastMessageAt: Date?
  let unreadCount: Int
}

struct WahaChatMessage: Sendable {
  let id: String
  let body: String
  let fromMe: Bool
  let from: String?
  let timestamp: Date
  let ackName: String?
}

struct WahaSendResult: Sendable {
  let providerMessageID: String?
  let accepted: Bool
  let failureReason: String?
}

final class WahaService: @unchecked Sendable {
  enum WahaError: Error, Sendable {
    case invalidResponse
    case httpStatus(Int, String)
    case missingValue(String)
  }

  private let baseURL: URL
  private let apiKey: String?
  private let sessionPrefix: String
  private let forceDefaultSession: Bool
  private let session: URLSession

  init(
    baseURL: URL,
    apiKey: String?,
    sessionPrefix: String,
    forceDefaultSession: Bool,
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.sessionPrefix = sessionPrefix
    self.forceDefaultSession = forceDefaultSession
    self.session = session
  }

  func sessionName(workspaceID: UUID) -> String {
    if forceDefaultSession {
      return "default"
    }
    return "\(sessionPrefix)_\(workspaceID.uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
  }

  func ensureSessionExistsAndStarted(workspaceID: UUID) async throws {
    let sessionName = sessionName(workspaceID: workspaceID)
    do {
      _ = try await getSessionStatus(sessionName: sessionName)
    } catch {
      _ = try await request(
        method: "POST",
        path: "/api/sessions",
        body: ["name": sessionName]
      )
    }

    do {
      _ = try await request(method: "POST", path: "/api/sessions/\(sessionName)/start", body: [:])
    } catch {
      // Ignore start conflicts when the session is already active.
    }
  }

  func getSessionStatus(workspaceID: UUID) async throws -> String {
    try await getSessionStatus(sessionName: sessionName(workspaceID: workspaceID))
  }

  func fetchQRCodeRaw(workspaceID: UUID) async throws -> String? {
    let sessionName = sessionName(workspaceID: workspaceID)
    let response = try await request(
      method: "GET",
      path: "/api/\(sessionName)/auth/qr",
      queryItems: [
        URLQueryItem(name: "format", value: "raw")
      ]
    )

    guard let payload = response as? [String: Any] else {
      return nil
    }

    if let raw = payload["value"] as? String, !raw.isEmpty {
      return raw
    }

    if let data = payload["data"] as? String, !data.isEmpty {
      return data
    }

    return nil
  }

  func fetchChatsOverview(workspaceID: UUID, limit: Int = 50) async throws -> [WahaChatOverview] {
    let sessionName = sessionName(workspaceID: workspaceID)
    let response = try await request(
      method: "GET",
      path: "/api/\(sessionName)/chats/overview",
      queryItems: [
        URLQueryItem(name: "limit", value: "\(limit)"),
        URLQueryItem(name: "offset", value: "0")
      ]
    )

    guard let array = response as? [[String: Any]] else {
      return []
    }

    return array.compactMap { item in
      guard let id = item["id"] as? String, !id.isEmpty else {
        return nil
      }

      let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let fallbackName = id.replacingOccurrences(of: "@c.us", with: "")
      let resolvedName = (name?.isEmpty == false) ? name! : fallbackName

      let lastMessage = item["lastMessage"] as? [String: Any]
      let body = (lastMessage?["body"] as? String) ?? ""
      let timestamp = parseUnixTimestamp(lastMessage?["timestamp"]) ?? Date()
      let unreadCount = extractUnreadCount(from: item)

      return WahaChatOverview(
        id: id,
        name: resolvedName,
        lastMessageBody: body,
        lastMessageAt: timestamp,
        unreadCount: unreadCount
      )
    }
  }

  func fetchMessages(workspaceID: UUID, chatID: String, limit: Int = 30) async throws -> [WahaChatMessage] {
    let sessionName = sessionName(workspaceID: workspaceID)
    let encodedChatID = chatID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chatID
    let response = try await request(
      method: "GET",
      path: "/api/\(sessionName)/chats/\(encodedChatID)/messages",
      queryItems: [
        URLQueryItem(name: "limit", value: "\(limit)"),
        URLQueryItem(name: "downloadMedia", value: "false")
      ]
    )

    guard let array = response as? [[String: Any]] else {
      return []
    }

    return array.compactMap { raw in
      guard let id = raw["id"] as? String,
            let body = raw["body"] as? String
      else {
        return nil
      }

      let fromMe = (raw["fromMe"] as? Bool) ?? false
      let timestamp = parseUnixTimestamp(raw["timestamp"]) ?? Date()
      let from = raw["from"] as? String
      let ackName = raw["ackName"] as? String

      return WahaChatMessage(
        id: id,
        body: body,
        fromMe: fromMe,
        from: from,
        timestamp: timestamp,
        ackName: ackName
      )
    }
  }

  func sendText(workspaceID: UUID, chatID: String, text: String) async throws -> WahaSendResult {
    let response = try await request(
      method: "POST",
      path: "/api/sendText",
      body: [
        "session": sessionName(workspaceID: workspaceID),
        "chatId": chatID,
        "text": text
      ]
    )

    let payload = response as? [String: Any]
    let message = payload?["message"] as? [String: Any]
    let messageID = (payload?["id"] as? String)
      ?? (message?["id"] as? String)

    return WahaSendResult(providerMessageID: messageID, accepted: true, failureReason: nil)
  }

  private func getSessionStatus(sessionName: String) async throws -> String {
    let response = try await request(method: "GET", path: "/api/sessions/\(sessionName)")
    guard let payload = response as? [String: Any] else {
      throw WahaError.invalidResponse
    }

    if let status = payload["status"] as? String, !status.isEmpty {
      return status
    }

    if let me = payload["me"] as? [String: Any], (me["id"] as? String)?.isEmpty == false {
      return "WORKING"
    }

    throw WahaError.missingValue("status")
  }

  private func request(
    method: String,
    path: String,
    queryItems: [URLQueryItem] = [],
    body: [String: Any]? = nil
  ) async throws -> Any {
    guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
      throw WahaError.invalidResponse
    }
    if !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    guard let url = components.url else {
      throw WahaError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 20
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    if let apiKey, !apiKey.isEmpty {
      request.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")
    }

    if let body {
      request.addValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw WahaError.invalidResponse
    }

    if !(200...299).contains(http.statusCode) {
      let bodyText = String(data: data, encoding: .utf8) ?? ""
      throw WahaError.httpStatus(http.statusCode, bodyText)
    }

    if data.isEmpty {
      return [:]
    }

    return try JSONSerialization.jsonObject(with: data)
  }

  private func parseUnixTimestamp(_ value: Any?) -> Date? {
    if let intValue = value as? Int {
      return Date(timeIntervalSince1970: TimeInterval(intValue))
    }
    if let doubleValue = value as? Double {
      return Date(timeIntervalSince1970: doubleValue)
    }
    if let stringValue = value as? String, let doubleValue = Double(stringValue) {
      return Date(timeIntervalSince1970: doubleValue)
    }
    return nil
  }

  private func extractUnreadCount(from payload: [String: Any]) -> Int {
    if let unread = payload["unreadCount"] as? Int {
      return unread
    }
    if let chat = payload["_chat"] as? [String: Any], let unread = chat["unreadCount"] as? Int {
      return unread
    }
    return 0
  }
}

func mapWahaStatusToConnectivity(_ status: String) -> ConnectivityState {
  let normalized = status.uppercased()
  switch normalized {
  case "WORKING":
    return .connected
  case "SCAN_QR", "PAIRING_CODE":
    return .qrRequired
  case "STARTING":
    return .connecting
  case "FAILED":
    return .disconnected
  default:
    return .degraded
  }
}

func mapWahaStatusToWorkerState(_ status: String) -> WorkerState {
  let normalized = status.uppercased()
  switch normalized {
  case "WORKING":
    return .running
  case "SCAN_QR", "STARTING", "PAIRING_CODE":
    return .provisioning
  case "FAILED":
    return .failed
  default:
    return .retrying
  }
}

func mapWahaAckToDelivery(_ ackName: String?) -> DeliveryStatus {
  let normalized = (ackName ?? "").uppercased()
  if normalized.contains("READ") || normalized.contains("PLAYED") {
    return .read
  }
  if normalized.contains("DELIVERED") {
    return .delivered
  }
  if normalized.contains("SENT") || normalized.contains("ACK") {
    return .sent
  }
  return .pending
}
