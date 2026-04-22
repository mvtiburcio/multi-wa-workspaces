import Testing
import WebKit
@testable import WorkspaceSession
import WorkspaceDomain

@MainActor
struct WebViewPoolTests {
  @Test
  func keepsAllWebViewsWarmByDefault() {
    let pool = WebViewPool()
    let a = Workspace(name: "A", colorTag: "blue")
    let b = Workspace(name: "B", colorTag: "green")
    let c = Workspace(name: "C", colorTag: "orange")

    _ = pool.webView(for: a)
    _ = pool.webView(for: b)
    _ = pool.webView(for: c)

    let cachedIDs = Set(pool.cachedWorkspaceIDs)
    #expect(cachedIDs.count == 3)
    #expect(cachedIDs.contains(a.id))
    #expect(cachedIDs.contains(b.id))
    #expect(cachedIDs.contains(c.id))
  }

  @Test
  func reusesWebViewForSameWorkspace() {
    let pool = WebViewPool(maxWarmWebViews: 2)
    let workspace = Workspace(name: "Alpha", colorTag: "blue")

    let first = pool.webView(for: workspace)
    let second = pool.webView(for: workspace)

    #expect(first === second)
  }

  @Test
  func evictsLeastRecentlyUsedWhenCapacityIsExceeded() {
    let pool = WebViewPool(maxWarmWebViews: 2)

    let a = Workspace(name: "A", colorTag: "blue")
    let b = Workspace(name: "B", colorTag: "green")
    let c = Workspace(name: "C", colorTag: "orange")

    _ = pool.webView(for: a)
    _ = pool.webView(for: b)
    _ = pool.webView(for: c)

    let cachedIDs = Set(pool.cachedWorkspaceIDs)
    #expect(cachedIDs.count == 2)
    #expect(!cachedIDs.contains(a.id))
    #expect(cachedIDs.contains(b.id))
    #expect(cachedIDs.contains(c.id))
  }
}
