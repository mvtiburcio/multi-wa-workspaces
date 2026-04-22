import Foundation
import WorkspaceBridgeContracts

public enum HTTPBridgeClientError: Error {
  case invalidResponse
  case httpStatus(Int)
  case missingSSEData
}

public final class HTTPBridgeClient: SessionBridgeClient, @unchecked Sendable {
  private let baseURL: URL
  private let token: String
  private let retryPolicy: BridgeRetryPolicy
  private let session: URLSession
  private let encoder = BridgeCodec.makeEncoder()
  private let decoder = BridgeCodec.makeDecoder()

  public init(
    baseURL: URL,
    token: String,
    retryPolicy: BridgeRetryPolicy = BridgeRetryPolicy(maxAttempts: 5, initialDelayMilliseconds: 500, maxDelayMilliseconds: 10_000, backoff: .exponential),
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.token = token
    self.retryPolicy = retryPolicy
    self.session = session
  }

  public convenience init(configuration: BridgeClientConfiguration, session: URLSession = .shared) {
    self.init(
      baseURL: configuration.baseURL,
      token: configuration.token,
      retryPolicy: configuration.retryPolicy,
      session: session
    )
  }

  public func fetchWorkspaceList() async throws -> [WorkspaceSnapshot] {
    let url = baseURL.appending(path: "/v1/workspaces")
    var request = URLRequest(url: url)
    applyHeaders(&request)
    request.httpMethod = "GET"

    let (data, response) = try await executeWithRetry(request: request)
    try validate(response: response)
    return try decoder.decode([WorkspaceSnapshot].self, from: data)
  }

  public func createWorkspace(_ requestPayload: CreateWorkspaceRequest) async throws -> WorkspaceSnapshot {
    let url = baseURL.appending(path: "/v1/workspaces")
    var request = URLRequest(url: url)
    applyHeaders(&request)
    request.httpMethod = "POST"
    request.httpBody = try encoder.encode(requestPayload)

    let (data, response) = try await executeWithRetry(request: request)
    try validate(response: response)
    return try decoder.decode(WorkspaceSnapshot.self, from: data)
  }

  public func fetchSnapshot(for workspaceID: UUID) async throws -> BridgeEnvelope<SyncSnapshotPayload> {
    let url = baseURL.appending(path: "/v1/workspaces/\(workspaceID.uuidString)/sync")
    var request = URLRequest(url: url)
    applyHeaders(&request)
    request.httpMethod = "POST"

    let (data, response) = try await executeWithRetry(request: request)
    try validate(response: response)
    return try decoder.decode(BridgeEnvelope<SyncSnapshotPayload>.self, from: data)
  }

  public func events(for workspaceID: UUID) -> AsyncThrowingStream<BridgeEnvelope<SyncDeltaPayload>, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          do {
            let url = baseURL.appending(path: "/v1/workspaces/\(workspaceID.uuidString)/events")
            var request = URLRequest(url: url)
            applyHeaders(&request)
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            let (data, response) = try await executeWithRetry(request: request)
            try validate(response: response)

            let payload = String(decoding: data, as: UTF8.self)
            guard let dataLine = payload.split(separator: "\n").first(where: { $0.hasPrefix("data:") }) else {
              throw HTTPBridgeClientError.missingSSEData
            }

            let json = dataLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let jsonData = json.data(using: .utf8) else {
              throw HTTPBridgeClientError.missingSSEData
            }

            let envelope = try decoder.decode(BridgeEnvelope<SyncDeltaPayload>.self, from: jsonData)
            continuation.yield(envelope)

            try await Task.sleep(for: .milliseconds(900))
          } catch {
            continuation.finish(throwing: error)
            return
          }
        }

        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  public func send(_ command: SendMessageCommand) async throws -> SendMessageResult {
    let url = baseURL.appending(path: "/v1/workspaces/\(command.workspaceID.uuidString)/messages/send")
    var request = URLRequest(url: url)
    applyHeaders(&request)
    request.httpMethod = "POST"
    request.httpBody = try encoder.encode(command)

    let (data, response) = try await executeWithRetry(request: request)
    try validate(response: response)
    return try decoder.decode(SendMessageResult.self, from: data)
  }

  public func fetchQRCode(for workspaceID: UUID) async throws -> BridgeEnvelope<WorkspaceQRState> {
    let url = baseURL.appending(path: "/v1/workspaces/\(workspaceID.uuidString)/qr")
    var request = URLRequest(url: url)
    applyHeaders(&request)
    request.httpMethod = "GET"

    let (data, response) = try await executeWithRetry(request: request)
    try validate(response: response)
    return try decoder.decode(BridgeEnvelope<WorkspaceQRState>.self, from: data)
  }

  private func applyHeaders(_ request: inout URLRequest) {
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }

  private func validate(response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
      throw HTTPBridgeClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      throw HTTPBridgeClientError.httpStatus(http.statusCode)
    }
  }

  private func executeWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
    var attempt = 0

    while true {
      if Task.isCancelled {
        throw CancellationError()
      }

      attempt += 1
      do {
        let result = try await session.data(for: request)
        try validate(response: result.1)
        return result
      } catch {
        guard shouldRetry(error: error), attempt < retryPolicy.maxAttempts else {
          throw error
        }
        try await Task.sleep(nanoseconds: backoffDelayNanoseconds(forAttempt: attempt))
      }
    }
  }

  private func shouldRetry(error: Error) -> Bool {
    if let bridgeError = error as? HTTPBridgeClientError {
      switch bridgeError {
      case .httpStatus(let statusCode):
        return [408, 425, 429, 500, 502, 503, 504].contains(statusCode)
      case .invalidResponse, .missingSSEData:
        return false
      }
    }

    if let urlError = error as? URLError {
      switch urlError.code {
      case .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
        return true
      default:
        return false
      }
    }

    return false
  }

  private func backoffDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
    let initial = max(0, retryPolicy.initialDelayMilliseconds)
    let maxDelay = max(initial, retryPolicy.maxDelayMilliseconds)
    let delayMilliseconds: Int

    switch retryPolicy.backoff {
    case .none:
      delayMilliseconds = 0
    case .linear:
      delayMilliseconds = min(maxDelay, initial * attempt)
    case .exponential:
      let factor = 1 << max(0, attempt - 1)
      delayMilliseconds = min(maxDelay, initial * factor)
    }

    return UInt64(delayMilliseconds) * 1_000_000
  }
}
