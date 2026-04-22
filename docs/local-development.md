# Desenvolvimento Local

## Pré-requisitos
- macOS 14+
- Xcode com Swift 6+
- acesso à internet para abrir `https://web.whatsapp.com`

## Build e testes
```bash
swift build
swift test
```

## Execução da aplicação
```bash
swift run WASpaces
```

## Módulos de código
- `packages/WorkspaceDomain`: contratos públicos (`Workspace`, `WorkspaceState`, protocolos e erros).
- `packages/WorkspacePersistence`: implementação SwiftData (`WorkspaceRecord`, `SwiftDataWorkspaceStore`).
- `packages/WorkspaceSession`: `WebSessionEngine`, `WebViewPool`, gerenciamento de `WKWebsiteDataStore`.
- `packages/WorkspaceApplicationServices`: `WorkspaceManager`, regras de negócio e logs.
- `apps/MultiWAWorkspacesApp`: shell SwiftUI macOS.

## Segurança
- nunca commitar `.env` real, token ou credenciais;
- mantenha placeholders em configuração;
- execute revisão de diff antes de push.
