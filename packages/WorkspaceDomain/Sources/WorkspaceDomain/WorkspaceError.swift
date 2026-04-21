import Foundation

public enum WorkspaceError: LocalizedError, Sendable {
  case workspaceNotFound(UUID)
  case invalidWorkspaceName
  case duplicateWorkspaceName
  case sessionTeardownFailed(UUID, String)
  case dataStoreRemovalFailed(UUID, String)

  public var errorDescription: String? {
    switch self {
    case let .workspaceNotFound(id):
      return "Workspace não encontrado: \(id.uuidString)."
    case .invalidWorkspaceName:
      return "Nome do workspace inválido."
    case .duplicateWorkspaceName:
      return "Já existe workspace com esse nome."
    case let .sessionTeardownFailed(id, reason):
      return "Falha ao encerrar sessão do workspace \(id.uuidString): \(reason)"
    case let .dataStoreRemovalFailed(id, reason):
      return "Falha ao remover data store do workspace \(id.uuidString): \(reason)"
    }
  }
}
