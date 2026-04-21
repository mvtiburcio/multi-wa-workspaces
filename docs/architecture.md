# Arquitetura

## Camadas
1. App Shell (SwiftUI): navegação, workspaces, UX.
2. Session Engine (WebKit): criação e ciclo de vida das webviews.
3. Session Persistence: isolamento por `WKWebsiteDataStore`.
4. Metadata Store: persistência local de configuração dos workspaces.

## Componentes sugeridos
- `WorkspaceManager`
- `WebSessionEngine`
- `WebViewPool`
- `WorkspaceStore`
- `StateMonitor`

## Diretrizes
- isolamento forte entre workspaces;
- nenhum segredo em repositório;
- observabilidade desde a POC;
- design para falha e recuperação.
