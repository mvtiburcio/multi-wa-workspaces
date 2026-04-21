import SwiftUI
import WorkspaceApplicationServices
import WorkspacePersistence
import WorkspaceSession

@main
struct MultiWAWorkspacesApp: App {
  @StateObject private var manager: WorkspaceManager

  init() {
    do {
      let store = try WorkspaceStoreFactory.makeDefaultStore()
      let session = WebSessionEngine(pool: WebViewPool(maxWarmWebViews: 2))
      _manager = StateObject(wrappedValue: WorkspaceManager(store: store, sessionController: session))
    } catch {
      fatalError("Falha ao iniciar dependências da aplicação: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      WorkspaceShellView(manager: manager)
        .task {
          await manager.refresh()
        }
    }
    .defaultSize(width: 1_420, height: 920)
  }
}
