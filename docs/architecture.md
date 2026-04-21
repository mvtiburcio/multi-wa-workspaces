# Arquitetura

## Camadas
1. App Shell (SwiftUI): navegação, lista de workspaces e fluxo de operação.
2. Application Services: regras de negócio e orquestração de ciclo de vida.
3. Session Engine (WebKit): criação e gerenciamento de webviews por workspace.
4. Session Persistence: isolamento por `WKWebsiteDataStore`.
5. Metadata Store: persistência local de configuração via SwiftData.

## Componentes implementados
- `WorkspaceManager` (`packages/WorkspaceApplicationServices`)
- `WebSessionEngine` (`packages/WorkspaceSession`)
- `WebViewPool` (`packages/WorkspaceSession`)
- `SwiftDataWorkspaceStore` (`packages/WorkspacePersistence`)
- `WorkspaceShellView` (`apps/MultiWAWorkspacesApp`)

## Diretrizes
- isolamento forte entre workspaces;
- nenhum segredo em repositório;
- observabilidade desde a POC;
- design para falha e recuperação.
