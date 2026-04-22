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
swift run WASpacesMac
# compatível com alias legado:
swift run WASpaces
# target iOS (stub em host macOS):
swift run WASpacesiOS
# Session Bridge MVP local (SQLite)
swift run SessionBridgeServer
# gerar projeto iOS nativo instalável
xcodegen generate --spec apps/WASpacesiOSApp/project.yml
```

## Rodar app iOS no simulador
```bash
xcodebuild -project apps/WASpacesiOSApp/WASpacesiOSApp.xcodeproj -scheme WASpacesiOSApp -showdestinations
xcodebuild -project apps/WASpacesiOSApp/WASpacesiOSApp.xcodeproj -scheme WASpacesiOSApp -destination "generic/platform=iOS Simulator" build CODE_SIGNING_ALLOWED=NO
```

## Configuração do modo de dados (iOS)
Por padrão, o app iOS sobe em modo demo (`WASPACES_IOS_USE_MOCK=1`) para garantir UI funcional sem bridge local.

Para usar bridge real:
```bash
export WASPACES_IOS_USE_MOCK=0
export WASPACES_BRIDGE_BASE_URL=http://127.0.0.1:8080
export WASPACES_BRIDGE_API_TOKEN=dev-local-token
```

## Módulos de código
- `packages/WorkspaceDomain`: contratos públicos (`Workspace`, `WorkspaceState`, protocolos e erros).
- `packages/WorkspacePersistence`: implementação SwiftData (`WorkspaceRecord`, `SwiftDataWorkspaceStore`).
- `packages/WorkspaceSession`: `WebSessionEngine`, `WebViewPool`, gerenciamento de `WKWebsiteDataStore`.
- `packages/WorkspaceApplicationServices`: `WorkspaceManager`, regras de negócio e logs.
- `apps/MultiWAWorkspacesApp`: shell SwiftUI macOS.
- `packages/WorkspaceBridgeContracts`: contratos versionados do Session Bridge.
- `apps/WASpacesiOS`: core iOS (`Workspaces -> Inbox -> Thread -> Envio`) com providers mock/HTTP.
- `apps/WASpacesiOSApp`: projeto iOS nativo para instalação em simulador.
- `bridge/SessionBridgeServer`: backend bridge com auth Bearer, SSE e persistência SQLite.

## Segurança
- nunca commitar `.env` real, token ou credenciais;
- mantenha placeholders em configuração;
- execute revisão de diff antes de push.
