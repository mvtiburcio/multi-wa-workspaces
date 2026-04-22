import Foundation
import SwiftData
import WorkspaceDomain

@Model
public final class WorkspaceRecord {
  @Attribute(.unique)
  public var id: UUID
  public var name: String
  public var colorTag: String
  public var dataStoreID: UUID
  public var stateRawValue: String
  public var sortOrder: Int?
  public var iconAssetPath: String?
  public var createdAt: Date
  public var lastOpenedAt: Date?

  public init(
    id: UUID,
    name: String,
    colorTag: String,
    dataStoreID: UUID,
    stateRawValue: String,
    sortOrder: Int?,
    iconAssetPath: String?,
    createdAt: Date,
    lastOpenedAt: Date?
  ) {
    self.id = id
    self.name = name
    self.colorTag = colorTag
    self.dataStoreID = dataStoreID
    self.stateRawValue = stateRawValue
    self.sortOrder = sortOrder
    self.iconAssetPath = iconAssetPath
    self.createdAt = createdAt
    self.lastOpenedAt = lastOpenedAt
  }
}

extension WorkspaceRecord {
  func asWorkspace() -> Workspace {
    Workspace(
      id: id,
      name: name,
      colorTag: colorTag,
      dataStoreID: dataStoreID,
      state: WorkspaceState(rawValue: stateRawValue) ?? .failed,
      iconAssetPath: iconAssetPath,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt
    )
  }
}
