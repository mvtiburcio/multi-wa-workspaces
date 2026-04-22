import Foundation
import UserNotifications

@MainActor
final class WorkspaceNotificationCenter {
  private var isPrepared = false

  func prepare() async {
    guard supportsSystemNotifications else {
      return
    }

    guard !isPrepared else {
      return
    }

    do {
      let center = UNUserNotificationCenter.current()
      _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      isPrepared = true
    } catch {
      isPrepared = false
    }
  }

  func send(title: String, body: String) async {
    guard supportsSystemNotifications else {
      return
    }

    if !isPrepared {
      await prepare()
    }

    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    do {
      try await center.add(request)
    } catch {
      // Keep app flow resilient even if the OS notification center rejects the request.
    }
  }

  private var supportsSystemNotifications: Bool {
    Bundle.main.bundleURL.pathExtension.lowercased() == "app"
  }
}
