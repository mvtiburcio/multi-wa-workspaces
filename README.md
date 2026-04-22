# WASpace

Projeto open source para operar múltiplos workspaces com isolamento de sessão.
Atualmente, a base implementada em produção interna está no runtime WebKit (macOS + iOS), mantendo Session Bridge Cloud em trilha paralela.

## Status

`POC macOS v1 implementada` em 21 de abril de 2026.
`Planejamento iOS Native UI` documentado em 22 de abril de 2026.
`Implementação iOS + Session Bridge MVP` iniciada em 22 de abril de 2026 (internal-only).
`Migração iOS para runtime WebKit` concluída em 22 de abril de 2026 (internal-only).

Entregue nesta versão:

- criação, seleção, renomeação e remoção de workspaces;
- isolamento de sessão por `WKWebsiteDataStore` com `UUID` dedicado;
- persistência local de metadados com SwiftData;
- pool de `WKWebView` mantendo sessões ativas em paralelo;
- shell nativo macOS com rail recolhido (todos os workspaces) e flyout por hover no menu;
- ações `Editar` e `Config` no cabeçalho do flyout (sem abas), com reordenação e exclusão em lote;
- foto opcional por workspace com recorte manual (zoom + arraste) e persistência local no App Support;
- badges de mensagens não lidas no rail e no flyout sem clipping visual;
- configurações funcionais locais (badges, notificações e workspace padrão, com ações de manutenção);
- remoção resiliente de workspace quando datastore estiver temporariamente em uso (fila local de limpeza pendente);
- testes unitários/integrados e CI com build/test macOS;
- Session Bridge MVP com `Swift Vapor + SQLite + Bearer Token` (`sync`, `events`, `send`, `qr`);
- app iOS nativo gerado por `xcodegen` em `apps/WASpacesiOSApp`, com runtime WebKit e isolamento real por workspace;
- UX iOS com abas `Chats`, `Atualizações`, `Chamadas`, `Ajustes`, switcher de workspace e sessão real `web.whatsapp.com` embutida;
- bridge com erros padronizados (`BridgeErrorEnvelope`), retry/backoff configurável no client e fila interna de notificações (`/notifications`) sem APNs real nesta etapa.
- bridge com provider real opcional WAHA para sessão por workspace (QR/sync/send) via variáveis `WASPACES_BRIDGE_WAHA_*`.

## Requisitos

- macOS 14+
- Xcode com Swift 6+

## Execução Local

```bash
swift build
swift test
swift run WASpacesMac
# legado compatível:
swift run WASpaces
# target iOS (host macOS mostra stub)
swift run WASpacesiOS
# Session Bridge MVP
swift run SessionBridgeServer
# gerar projeto iOS instalável
xcodegen generate --spec apps/WASpacesiOSApp/project.yml
```

## Estrutura

- `apps/MultiWAWorkspacesApp`: app macOS (SwiftUI)
- `packages/WorkspaceDomain`: modelos, protocolos e erros
- `packages/WorkspacePersistence`: persistência SwiftData
- `packages/WorkspaceSession`: engine WebKit, pool e datastore
- `packages/WorkspaceApplicationServices`: `WorkspaceManager` e orquestração
- `packages/WorkspaceBridgeContracts`: contratos de sync/realtime/send para Session Bridge
- `apps/WASpacesiOS`: app iOS com fluxo nativo e runtime WebKit (mantendo providers bridge no mesmo core para trilha cloud)
- `bridge/SessionBridgeServer`: backend bridge MVP (Vapor + SQLite + SSE + auth Bearer)
- `apps/WASpacesiOSApp`: projeto iOS nativo (`.xcodeproj`) para simulador/dispositivo

## Documentação

- [Visão do Projeto](./docs/project-overview.md)
- [Plano Técnico QR-only](./docs/technical-plan-qr-only.md)
- [Plano Técnico iOS Native UI](./docs/technical-plan-ios-native-ui.md)
- [PRD iOS](./docs/ios-prd.md)
- [Aceite iOS](./docs/ios-acceptance.md)
- [Arquitetura](./docs/architecture.md)
- [Roadmap](./docs/roadmap.md)
- [Guia de Desenvolvimento Local](./docs/local-development.md)
- [Deploy VPS](./docs/deployment-vps.md)
- [Critérios de Aceite da POC](./docs/poc-acceptance.md)
- [Riscos e Limites](./docs/risks-and-limits.md)
- [Session Bridge: Especificação Operacional](./docs/bridge/session-bridge-operational-spec.md)
- [Gate App Store: Checklist](./docs/compliance/app-store-gate-checklist.md)
- [Segurança Open Source](./docs/security-open-source.md)
- [ADR-0001: Estratégia de Sessões](./docs/adr/0001-workspace-session-isolation.md)
- [ADR-0002: iOS Native + Session Bridge](./docs/adr/0002-ios-native-session-bridge.md)

## Open Source

- Licença: [MIT](./LICENSE)
- Contribuição: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Conduta: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- Segurança: [SECURITY.md](./SECURITY.md)

## Aviso importante

A trilha atual opera em `internal-only` para validação técnica de iOS + Session Bridge e exige gate formal de conformidade App Store para distribuição pública. O uso de serviços de terceiros deve respeitar os termos e políticas vigentes desses serviços.
