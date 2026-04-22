import Foundation

enum WorkspaceFlyoutPanel: Equatable {
  case workspaces
  case config
}

struct WorkspaceFlyoutState: Equatable {
  var panel: WorkspaceFlyoutPanel = .workspaces
  var isEditing = false

  var canReorder: Bool {
    panel == .workspaces && isEditing
  }

  mutating func toggleEdit() {
    if panel == .config {
      panel = .workspaces
    }
    isEditing.toggle()
  }

  mutating func toggleConfig() {
    if panel == .config {
      panel = .workspaces
      return
    }

    panel = .config
    isEditing = false
  }
}
