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

## Configuração de dados (iOS real)
Por padrão, o app iOS sobe em modo real via WebKit (`web.whatsapp.com`) com isolamento por workspace.

Para trilha bridge cloud (opcional), use as variáveis abaixo:

Variáveis recomendadas:
```bash
export WASPACES_BRIDGE_BASE_URL=http://127.0.0.1:8080
export WASPACES_BRIDGE_API_TOKEN=dev-local-token
export WASPACES_BRIDGE_RETRY_MAX_ATTEMPTS=5
export WASPACES_BRIDGE_RETRY_INITIAL_DELAY_MS=500
export WASPACES_BRIDGE_RETRY_MAX_DELAY_MS=10000
export WASPACES_BRIDGE_RETRY_BACKOFF=exponential
export WASPACES_BRIDGE_SEED_MODE=none
export WASPACES_BRIDGE_WAHA_ENABLED=1
export WASPACES_WAHA_BASE_URL=http://127.0.0.1:3000
export WASPACES_WAHA_API_KEY=change-me
export WASPACES_WAHA_SESSION_PREFIX=ws
export WASPACES_WAHA_FORCE_DEFAULT_SESSION=0
```

Endpoints operacionais úteis da bridge local:
- `GET /v1/workspaces`
- `POST /v1/workspaces`
- `POST /v1/workspaces/{id}/sync`
- `GET /v1/workspaces/{id}/events`
- `POST /v1/workspaces/{id}/messages/send`
- `GET /v1/workspaces/{id}/qr`
- `GET /v1/workspaces/{id}/updates`
- `GET /v1/workspaces/{id}/calls`
- `GET /v1/workspaces/{id}/notifications`

## Módulos de código
- `packages/WorkspaceDomain`: contratos públicos (`Workspace`, `WorkspaceState`, protocolos e erros).
- `packages/WorkspacePersistence`: implementação SwiftData (`WorkspaceRecord`, `SwiftDataWorkspaceStore`).
- `packages/WorkspaceSession`: `WebSessionEngine`, `WebViewPool`, gerenciamento de `WKWebsiteDataStore`.
- `packages/WorkspaceApplicationServices`: `WorkspaceManager`, regras de negócio e logs.
- `apps/MultiWAWorkspacesApp`: shell SwiftUI macOS.
- `packages/WorkspaceBridgeContracts`: contratos versionados do Session Bridge.
- `apps/WASpacesiOS`: core iOS com runtime WebKit para `Chats` e providers bridge mantidos para trilha cloud.
- `apps/WASpacesiOSApp`: projeto iOS nativo para instalação em simulador.
- `bridge/SessionBridgeServer`: backend bridge com auth Bearer, SSE e persistência SQLite.

## Segurança
- nunca commitar `.env` real, token ou credenciais;
- mantenha placeholders em configuração;
- execute revisão de diff antes de push.
