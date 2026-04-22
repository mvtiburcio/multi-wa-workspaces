import AppKit
import Testing
@testable import WASpaces
import WorkspaceDomain

struct WASpacesTests {
  @Test
  @MainActor
  func settingsStorePersistsReducedShape() {
    let suiteName = "WorkspaceUISettingsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let first = WorkspaceUISettingsStore(userDefaults: defaults)
    let workspaceID = UUID()

    first.setNotificationsEnabled(false)
    first.setShowBadges(false)
    first.setDefaultWorkspaceID(workspaceID)

    let second = WorkspaceUISettingsStore(userDefaults: defaults)
    let loaded = second.settings

    #expect(loaded.notificationsEnabled == false)
    #expect(loaded.showBadges == false)
    #expect(loaded.defaultWorkspaceID == workspaceID)

    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test
  @MainActor
  func pendingDataStoreQueuePersistsAndDeduplicates() {
    let suiteName = "PendingDataStoreCleanupStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let storeA = PendingDataStoreCleanupStore(userDefaults: defaults)
    let first = UUID()
    let second = UUID()

    storeA.enqueue(first)
    storeA.enqueue(second)
    storeA.enqueue(first)

    let storeB = PendingDataStoreCleanupStore(userDefaults: defaults)
    #expect(storeB.all() == [first, second])

    storeB.remove(first)
    #expect(storeB.all() == [second])

    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test
  @MainActor
  func pendingCleanupProcessorRemovesSuccessfulEntries() async {
    let suiteName = "PendingDataStoreCleanupProcessorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let queue = PendingDataStoreCleanupStore(userDefaults: defaults)
    let a = UUID()
    let b = UUID()
    queue.enqueue(a)
    queue.enqueue(b)

    var removed: [UUID] = []
    let processor = PendingDataStoreCleanupProcessor(
      queueStore: queue,
      remover: { id in
        removed.append(id)
      },
      isRecoverableError: { _ in false }
    )

    await processor.processPending()

    #expect(Set(removed) == Set([a, b]))
    #expect(queue.all().isEmpty)

    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test
  func flyoutStateToggleEnsuresEditAndConfigExclusivity() {
    var state = WorkspaceFlyoutState()

    #expect(state.panel == .workspaces)
    #expect(state.isEditing == false)

    state.toggleEdit()
    #expect(state.canReorder == true)

    state.toggleConfig()
    #expect(state.panel == .config)
    #expect(state.isEditing == false)

    state.toggleConfig()
    #expect(state.panel == .workspaces)
    #expect(state.isEditing == false)
  }

  @Test
  func preferredWorkspaceFallbackWhenDefaultIsMissing() {
    let existing = Workspace(name: "A", colorTag: "blue")
    let missing = UUID()

    let selected = WorkspaceSelectionDefaults.preferredWorkspaceID(
      defaultID: missing,
      workspaces: [existing]
    )

    #expect(selected == existing.id)
    #expect(
      WorkspaceSelectionDefaults.sanitizedDefaultID(
        defaultID: missing,
        availableIDs: [existing.id]
      ) == nil
    )
  }

  @Test
  func avatarCropRendererOutputsSquarePNG() throws {
    let source = makeTestImage(width: 1200, height: 800)
    let state = WorkspaceAvatarCropState(zoom: 1.6, offset: CGSize(width: 35, height: -20))

    let data = try WorkspaceAvatarCropRenderer.renderPNG(from: source, state: state)
    let rep = NSBitmapImageRep(data: data)

    #expect(rep != nil)
    #expect(rep?.pixelsWide == WorkspaceAvatarCropRenderer.outputPixels)
    #expect(rep?.pixelsHigh == WorkspaceAvatarCropRenderer.outputPixels)
  }

  @Test
  func unreadBadgeFormatterUsesExpectedLabels() {
    #expect(WorkspaceUnreadBadgeFormatter.text(for: 1) == "1")
    #expect(WorkspaceUnreadBadgeFormatter.text(for: 99) == "99")
    #expect(WorkspaceUnreadBadgeFormatter.text(for: 100) == "99+")
  }

  @Test
  func smoke() {
    #expect(Bool(true))
  }

  private func makeTestImage(width: CGFloat, height: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()

    NSColor.systemTeal.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width / 2, height: height)).fill()

    NSColor.systemOrange.setFill()
    NSBezierPath(rect: NSRect(x: width / 2, y: 0, width: width / 2, height: height)).fill()

    image.unlockFocus()
    return image
  }
}
