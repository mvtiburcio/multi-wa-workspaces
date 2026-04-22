# WASpaces

Projeto open source para operar múltiplos workspaces com isolamento de sessão.
Atualmente, a base implementada está na POC macOS via WebKit. A trilha iOS nativa já está planejada com Session Bridge Cloud.

## Status

`POC macOS v1 implementada` em 21 de abril de 2026.
`Planejamento iOS Native UI` documentado em 22 de abril de 2026.

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
- testes unitários/integrados e CI com build/test macOS.

## Requisitos

- macOS 14+
- Xcode com Swift 6+

## Execução Local

```bash
swift build
swift test
swift run WASpaces
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
- [Plano Técnico iOS Native UI](./docs/technical-plan-ios-native-ui.md)
- [PRD iOS](./docs/ios-prd.md)
- [Aceite iOS](./docs/ios-acceptance.md)
- [Arquitetura](./docs/architecture.md)
- [Roadmap](./docs/roadmap.md)
- [Guia de Desenvolvimento Local](./docs/local-development.md)
- [Critérios de Aceite da POC](./docs/poc-acceptance.md)
- [Riscos e Limites](./docs/risks-and-limits.md)
- [Segurança Open Source](./docs/security-open-source.md)
- [ADR-0001: Estratégia de Sessões](./docs/adr/0001-workspace-session-isolation.md)
- [ADR-0002: iOS Native + Session Bridge](./docs/adr/0002-ios-native-session-bridge.md)

## Open Source

- Licença: [MIT](./LICENSE)
- Contribuição: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Conduta: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- Segurança: [SECURITY.md](./SECURITY.md)

## Aviso importante

A POC atual segue o modelo QR-only em WebKit no macOS. A trilha iOS exige gate obrigatório de conformidade App Store e arquitetura com Session Bridge Cloud antes da codificação. O uso de serviços de terceiros deve respeitar os termos e políticas vigentes desses serviços.
