import Foundation
import WorkspaceDomain

enum WorkspaceSelectionDefaults {
  static func preferredWorkspaceID(defaultID: UUID?, workspaces: [Workspace]) -> UUID? {
    if let defaultID, workspaces.contains(where: { $0.id == defaultID }) {
      return defaultID
    }
    return workspaces.first?.id
  }

  static func sanitizedDefaultID(defaultID: UUID?, availableIDs: [UUID]) -> UUID? {
    guard let defaultID else {
      return nil
    }
    return availableIDs.contains(defaultID) ? defaultID : nil
  }
}
