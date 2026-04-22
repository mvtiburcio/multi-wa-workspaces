# ADR-0002: iOS Native com Session Bridge Cloud

## Status

Aceita

## Contexto

A POC macOS QR-only validou isolamento por workspace. Para iOS, o objetivo v1 é experiência nativa completa com atualização contínua em foreground/background.

Limite identificado:

- estratégia local-only no iOS não sustenta tempo real contínuo em background com confiabilidade operacional.

## Decisão

Adotar arquitetura com:

1. app iOS `iPhone-first` com UI 100% nativa;
2. Session Bridge Cloud com worker dedicado por workspace;
3. fallback híbrido obrigatório para WebView apenas em degradação controlada.

## Consequências

### Positivas

- viabiliza tempo real contínuo com app em background;
- desacopla renderização nativa das mudanças visuais da origem web;
- melhora observabilidade e controle operacional por workspace.

### Negativas

- aumenta custo e complexidade operacional (workers, filas, observabilidade);
- exige governança de segurança/compliance mais rígida;
- adiciona dependência de infraestrutura cloud para SLOs de UX.

## Estratégias de Mitigação

- gate obrigatório de conformidade App Store antes da implementação iOS;
- contratos de dados versionados + testes de regressão de parsing;
- retries/backoff e replay por `SyncCursor`;
- runbooks e monitoramento por SLO de sync/render/envio.

## Relação com ADR anterior

- ADR-0001 permanece válida para isolamento por workspace na trilha macOS.
- ADR-0002 define a estratégia obrigatória para a trilha iOS nativa com tempo real total.
