import Foundation

public enum WorkspaceState: String, Codable, CaseIterable, Sendable {
  case cold
  case loading
  case qrRequired
  case connected
  case disconnected
  case failed
}

public struct Workspace: Identifiable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var colorTag: String
  public let dataStoreID: UUID
  public var state: WorkspaceState
  public let createdAt: Date
  public var lastOpenedAt: Date?

  public init(
    id: UUID = UUID(),
    name: String,
    colorTag: String,
    dataStoreID: UUID = UUID(),
    state: WorkspaceState = .cold,
    createdAt: Date = Date(),
    lastOpenedAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.colorTag = colorTag
    self.dataStoreID = dataStoreID
    self.state = state
    self.createdAt = createdAt
    self.lastOpenedAt = lastOpenedAt
  }
}
