import Foundation

enum WorkspaceUnreadBadgeFormatter {
  static func text(for unread: Int) -> String {
    guard unread > 0 else {
      return "0"
    }
    return unread > 99 ? "99+" : "\(unread)"
  }
}
