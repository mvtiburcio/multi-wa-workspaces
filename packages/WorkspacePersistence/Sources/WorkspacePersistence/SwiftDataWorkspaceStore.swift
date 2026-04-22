import Foundation
import SwiftData
import WorkspaceDomain

@MainActor
public final class SwiftDataWorkspaceStore: WorkspaceStoring {
  public let container: ModelContainer
  private let context: ModelContext

  public init(container: ModelContainer) {
    self.container = container
    self.context = ModelContext(container)
    self.context.autosaveEnabled = false
  }

  public func listWorkspaces() throws -> [Workspace] {
    let records = try fetchAllRecords()
    try backfillSortOrderIfNeeded(records)
    return orderedRecords(from: records).map { $0.asWorkspace() }
  }

  public func workspace(id: UUID) throws -> Workspace? {
    try fetchRecord(id: id)?.asWorkspace()
  }

  public func insert(_ workspace: Workspace) throws {
    try validateName(workspace.name, excluding: nil)
    let records = try fetchAllRecords()
    try backfillSortOrderIfNeeded(records)

    let record = WorkspaceRecord(
      id: workspace.id,
      name: workspace.name,
      colorTag: workspace.colorTag,
      dataStoreID: workspace.dataStoreID,
      stateRawValue: workspace.state.rawValue,
      sortOrder: nextSortOrderValue(in: records),
      iconAssetPath: workspace.iconAssetPath,
      createdAt: workspace.createdAt,
      lastOpenedAt: workspace.lastOpenedAt
    )
    context.insert(record)
    try save()
  }

  public func rename(id: UUID, newName: String) throws {
    let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw WorkspaceError.invalidWorkspaceName
    }
    guard let record = try fetchRecord(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    try validateName(normalizedName, excluding: id)
    record.name = normalizedName
    try save()
  }

  public func setIconAssetPath(id: UUID, iconAssetPath: String) throws {
    let normalizedPath = iconAssetPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedPath.isEmpty else {
      throw WorkspaceError.invalidIconAssetPath
    }

    guard let record = try fetchRecord(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    record.iconAssetPath = normalizedPath
    try save()
  }

  public func clearIconAssetPath(id: UUID) throws {
    guard let record = try fetchRecord(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    record.iconAssetPath = nil
    try save()
  }

  public func reorder(workspaceIDsInDisplayOrder: [UUID]) throws {
    let records = try fetchAllRecords()
    try backfillSortOrderIfNeeded(records)

    let recordIDs = Set(records.map(\.id))
    guard
      workspaceIDsInDisplayOrder.count == records.count,
      Set(workspaceIDsInDisplayOrder) == recordIDs
    else {
      throw WorkspaceError.invalidWorkspaceOrder
    }

    let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    for (index, workspaceID) in workspaceIDsInDisplayOrder.enumerated() {
      recordsByID[workspaceID]?.sortOrder = index
    }
    try save()
  }

  public func updateState(id: UUID, state: WorkspaceState) throws {
    guard let record = try fetchRecord(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    record.stateRawValue = state.rawValue
    try save()
  }

  public func updateLastOpenedAt(id: UUID, date: Date) throws {
    guard let record = try fetchRecord(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    record.lastOpenedAt = date
    try save()
  }

  public func delete(id: UUID) throws {
    guard let record = try fetchRecord(id: id) else {
      throw WorkspaceError.workspaceNotFound(id)
    }
    context.delete(record)
    try save()
  }

  private func fetchRecord(id: UUID) throws -> WorkspaceRecord? {
    let descriptor = FetchDescriptor<WorkspaceRecord>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }

  private func fetchAllRecords() throws -> [WorkspaceRecord] {
    try context.fetch(FetchDescriptor<WorkspaceRecord>())
  }

  private func validateName(_ name: String, excluding workspaceID: UUID?) throws {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw WorkspaceError.invalidWorkspaceName
    }

    let existing = try listWorkspaces().first { workspace in
      if let workspaceID, workspace.id == workspaceID {
        return false
      }
      return workspace.name.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    if existing != nil {
      throw WorkspaceError.duplicateWorkspaceName
    }
  }

  private func backfillSortOrderIfNeeded(_ records: [WorkspaceRecord]) throws {
    guard records.contains(where: { $0.sortOrder == nil }) else {
      return
    }

    let legacyOrdered = records.sorted { lhs, rhs in
      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
      }

      let nameComparison = lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive])
      if nameComparison != .orderedSame {
        return nameComparison == .orderedAscending
      }

      return lhs.id.uuidString < rhs.id.uuidString
    }

    for (index, record) in legacyOrdered.enumerated() {
      record.sortOrder = index
    }
    try save()
  }

  private func orderedRecords(from records: [WorkspaceRecord]) -> [WorkspaceRecord] {
    records.sorted { lhs, rhs in
      let leftOrder = lhs.sortOrder ?? Int.max
      let rightOrder = rhs.sortOrder ?? Int.max
      if leftOrder != rightOrder {
        return leftOrder < rightOrder
      }

      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt < rhs.createdAt
      }

      let nameComparison = lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive])
      if nameComparison != .orderedSame {
        return nameComparison == .orderedAscending
      }

      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private func nextSortOrderValue(in records: [WorkspaceRecord]) -> Int {
    let currentMax = records.compactMap(\.sortOrder).max() ?? -1
    return currentMax + 1
  }

  private func save() throws {
    if context.hasChanges {
      try context.save()
    }
  }
}

public enum WorkspaceStoreFactory {
  @MainActor
  public static func makeDefaultStore() throws -> SwiftDataWorkspaceStore {
    let configuration = ModelConfiguration("WorkspaceMetadata")
    let container = try ModelContainer(for: WorkspaceRecord.self, configurations: configuration)
    return SwiftDataWorkspaceStore(container: container)
  }

  @MainActor
  public static func makeInMemoryStore() throws -> SwiftDataWorkspaceStore {
    let configuration = ModelConfiguration("WorkspaceMetadataInMemory", isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: WorkspaceRecord.self, configurations: configuration)
    return SwiftDataWorkspaceStore(container: container)
  }
}
