# Workspaces QR for WhatsApp Web

Projeto open source para operar múltiplos workspaces de WhatsApp Web com isolamento de sessão por QR, usando app macOS em SwiftUI + WebKit.

## Status
`POC v1 implementada` em 21 de abril de 2026.

Entregue nesta versão:
- criação, seleção, renomeação e remoção de workspaces;
- isolamento de sessão por `WKWebsiteDataStore` com `UUID` dedicado;
- persistência local de metadados com SwiftData;
- pool de `WKWebView` com até 2 sessões aquecidas;
- shell nativo macOS com lista lateral e estado da sessão;
- testes unitários/integrados e CI com build/test macOS.

## Requisitos
- macOS 14+
- Xcode com Swift 6+

## Execução Local
```bash
swift build
swift test
swift run MultiWAWorkspacesApp
```

## Estrutura
- `apps/MultiWAWorkspacesApp`: app macOS (SwiftUI)
- `packages/WorkspaceDomain`: modelos, protocolos e erros
- `packages/WorkspacePersistence`: persistência SwiftData
- `packages/WorkspaceSession`: engine WebKit, pool e datastore
- `packages/WorkspaceApplicationServices`: `WorkspaceManager` e orquestração

## Documentação
- [Visão do Projeto](./docs/project-overview.md)
- [Plano Técnico QR-only](./docs/technical-plan-qr-only.md)
- [Arquitetura](./docs/architecture.md)
- [Roadmap](./docs/roadmap.md)
- [Guia de Desenvolvimento Local](./docs/local-development.md)
- [Critérios de Aceite da POC](./docs/poc-acceptance.md)
- [Riscos e Limites](./docs/risks-and-limits.md)
- [Segurança Open Source](./docs/security-open-source.md)
- [ADR-0001: Estratégia de Sessões](./docs/adr/0001-workspace-session-isolation.md)

## Open Source
- Licença: [MIT](./LICENSE)
- Contribuição: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Conduta: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- Segurança: [SECURITY.md](./SECURITY.md)

## Aviso importante
Este projeto segue o modelo QR-only em WebKit. O uso de serviços de terceiros deve respeitar os termos e políticas vigentes desses serviços.
