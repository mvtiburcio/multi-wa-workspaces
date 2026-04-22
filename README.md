# Workspaces QR for WhatsApp Web

Projeto open source para operar múltiplos workspaces de WhatsApp Web com isolamento de sessão por QR, usando app macOS em SwiftUI + WebKit.

## Status
`POC v1 implementada` em 21 de abril de 2026.

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
