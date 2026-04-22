import Foundation

struct WorkspaceUISettings: Codable, Equatable {
  var notificationsEnabled: Bool = true
  var showBadges: Bool = true
  var defaultWorkspaceID: UUID?
}

@MainActor
final class WorkspaceUISettingsStore: ObservableObject {
  @Published private(set) var settings: WorkspaceUISettings

  private let userDefaults: UserDefaults
  private let key = "workspace_ui_settings.v2"
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults

    if
      let data = userDefaults.data(forKey: key),
      let loaded = try? decoder.decode(WorkspaceUISettings.self, from: data)
    {
      settings = loaded
    } else {
      settings = WorkspaceUISettings()
    }
  }

  func setShowBadges(_ value: Bool) {
    update { $0.showBadges = value }
  }

  func setNotificationsEnabled(_ value: Bool) {
    update { $0.notificationsEnabled = value }
  }

  func setDefaultWorkspaceID(_ id: UUID?) {
    update { $0.defaultWorkspaceID = id }
  }

  private func update(_ mutate: (inout WorkspaceUISettings) -> Void) {
    var draft = settings
    mutate(&draft)

    guard draft != settings else {
      return
    }

    settings = draft
    persist(settings)
  }

  private func persist(_ settings: WorkspaceUISettings) {
    guard let data = try? encoder.encode(settings) else {
      return
    }
    userDefaults.set(data, forKey: key)
  }
}
