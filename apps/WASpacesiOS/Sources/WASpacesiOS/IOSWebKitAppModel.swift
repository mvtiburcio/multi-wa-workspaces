#if os(iOS)
import Combine
import Foundation
import WorkspaceApplicationServices
import WorkspaceDomain
import WorkspacePersistence
import WorkspaceSession

@MainActor
public final class IOSWebKitAppModel: ObservableObject {
  @Published public var isBootstrapping = false
  @Published public var bootstrapErrorMessage: String?
  @Published public var newWorkspaceName = ""

  public let manager: WorkspaceManager

  private var cancellables: Set<AnyCancellable> = []

  public init() throws {
    let store = try WorkspaceStoreFactory.makeDefaultStore()
    let session = WebSessionEngine(pool: WebViewPool())
    let manager = WorkspaceManager(store: store, sessionController: session)
    self.manager = manager

    manager.$workspaces
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    manager.$selectedWorkspaceID
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    manager.$selectedWebView
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
  }

  public var selectedWorkspace: Workspace? {
    guard let selectedWorkspaceID = manager.selectedWorkspaceID else {
      return nil
    }
    return manager.workspaces.first(where: { $0.id == selectedWorkspaceID })
  }

  public func bootstrap() async {
    if isBootstrapping {
      return
    }

    isBootstrapping = true
    bootstrapErrorMessage = nil

    do {
      await manager.refresh()

      if manager.workspaces.isEmpty {
        _ = try await manager.create(name: "Workspace 1")
      }

      if let selectedID = manager.selectedWorkspaceID {
        try await manager.select(id: selectedID)
      } else if let firstID = manager.workspaces.first?.id {
        try await manager.select(id: firstID)
      }
    } catch {
      bootstrapErrorMessage = "Falha ao iniciar sessões WebKit: \(error.localizedDescription)"
    }

    isBootstrapping = false
  }

  public func selectWorkspace(_ id: UUID) async {
    do {
      try await manager.select(id: id)
    } catch {
      bootstrapErrorMessage = "Falha ao selecionar workspace: \(error.localizedDescription)"
    }
  }

  public func createWorkspace() async {
    let trimmed = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }

    do {
      let created = try await manager.create(name: trimmed)
      newWorkspaceName = ""
      try await manager.select(id: created.id)
    } catch {
      bootstrapErrorMessage = "Falha ao criar workspace: \(error.localizedDescription)"
    }
  }

  public func removeWorkspace(_ id: UUID) async {
    do {
      try await manager.remove(id: id)
      if manager.selectedWorkspaceID == nil, let firstID = manager.workspaces.first?.id {
        try await manager.select(id: firstID)
      }
    } catch {
      bootstrapErrorMessage = "Falha ao remover workspace: \(error.localizedDescription)"
    }
  }

  public func reloadSelectedWorkspace() async {
    do {
      try await manager.reloadSelectedWorkspace()
    } catch {
      bootstrapErrorMessage = "Falha ao recarregar sessão: \(error.localizedDescription)"
    }
  }

  public func stateLabel(_ state: WorkspaceState) -> String {
    switch state {
    case .cold:
      return "Frio"
    case .loading:
      return "Carregando"
    case .qrRequired:
      return "QR necessário"
    case .connected:
      return "Conectado"
    case .disconnected:
      return "Desconectado"
    case .failed:
      return "Falha"
    }
  }
}
#endif
