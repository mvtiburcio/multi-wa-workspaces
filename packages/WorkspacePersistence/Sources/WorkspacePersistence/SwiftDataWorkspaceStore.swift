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
    let descriptor = FetchDescriptor<WorkspaceRecord>(
      sortBy: [
        SortDescriptor(\WorkspaceRecord.createdAt, order: .forward),
        SortDescriptor(\WorkspaceRecord.name, order: .forward)
      ]
    )
    return try context.fetch(descriptor).map { $0.asWorkspace() }
  }

  public func workspace(id: UUID) throws -> Workspace? {
    try fetchRecord(id: id)?.asWorkspace()
  }

  public func insert(_ workspace: Workspace) throws {
    try validateName(workspace.name, excluding: nil)
    let record = WorkspaceRecord(
      id: workspace.id,
      name: workspace.name,
      colorTag: workspace.colorTag,
      dataStoreID: workspace.dataStoreID,
      stateRawValue: workspace.state.rawValue,
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
