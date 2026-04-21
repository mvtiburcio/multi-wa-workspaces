# Workspaces QR for WhatsApp Web (Planning)

Repositório open source de **planejamento técnico** para um app interno multiplataforma (iOS, iPadOS e macOS) baseado em:
- Workspaces independentes;
- sessão por QR Code do WhatsApp Web;
- isolamento de sessão por workspace.

## Status
`Planning-only` (sem implementação de produção neste repositório).

## Objetivo
Documentar arquitetura, riscos, decisões e roadmap antes do desenvolvimento.

## Escopo atual
- requisitos funcionais e não funcionais;
- arquitetura proposta;
- riscos técnicos e de conformidade;
- plano por fases (POC -> MVP -> robustez);
- padrões de segurança para projeto open source.

## O que **não** entra neste repositório (por política)
- credenciais reais;
- tokens, chaves privadas e segredos de produção;
- endpoints internos não públicos;
- scripts de deploy com dados sensíveis.

## Documentação
- [Visão do Projeto](./docs/project-overview.md)
- [Plano Técnico QR-only](./docs/technical-plan-qr-only.md)
- [Arquitetura](./docs/architecture.md)
- [Roadmap](./docs/roadmap.md)
- [Riscos e Limites](./docs/risks-and-limits.md)
- [Segurança Open Source](./docs/security-open-source.md)
- [ADR-0001: Estratégia de Sessões](./docs/adr/0001-workspace-session-isolation.md)

## Open Source
- Licença: [MIT](./LICENSE)
- Contribuição: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Conduta: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- Segurança: [SECURITY.md](./SECURITY.md)

## Aviso importante
Este projeto é um planejamento técnico. O uso de serviços de terceiros deve respeitar os termos e políticas vigentes desses serviços.
