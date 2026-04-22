# Roadmap

## Fase 0 - Planejamento Base (concluída)

- consolidar requisitos iniciais de `multi-workspace`;
- documentar arquitetura macOS POC;
- preparar repositório open source e governança.

## Fase 1 - POC macOS QR-only (concluída)

Data de referência: 21 de abril de 2026.

- [x] criação/renomeação/remoção de workspace;
- [x] isolamento de sessão por `WKWebsiteDataStore`;
- [x] persistência local com SwiftData;
- [x] rail + flyout e operações de edição/reordenação;
- [x] tratamento de remoção resiliente de datastore em uso;
- [x] testes unitários/integração e CI macOS.

## Fase 2 - Gate de Conformidade App Store (obrigatória para release iOS)

Status: em andamento.

Critério de go/no-go:

- validar enquadramento de política de distribuição App Store;
- validar riscos legais e termos de uso de terceiros;
- definir plano de incidentes/compliance antes de codificação iOS;
- registrar decisão formal do gate com aprovação de produto e engenharia.

Saída esperada:

- checklist de conformidade assinado;
- matriz de riscos com mitigação aceita;
- decisão formal de continuidade para a trilha iOS.

## Fase 3 - iOS Full Native (iPhone-first)

Status: em andamento (Sprint 1 internal-only).

Escopo funcional v1:

- onboarding por QR para vínculo de workspace;
- inbox nativa completa com busca, filtros e estados;
- thread nativa completa com composer, envio e status de entrega;
- alternância de workspace sem vazamento;
- cache local e sincronização incremental.

Regras desta fase:

- UI/UX 100% nativa iOS (não replicar design do WhatsApp Web);
- parsing e normalização orientados a contrato interno de dados;
- fallback híbrido controlado quando parser falhar.
- sem `go` formal de compliance, build iOS não segue para distribuição pública.

## Fase 4 - Session Bridge Cloud (tempo real contínuo)

Status: pendente.

Escopo:

- worker dedicado por workspace para manter sessão e coleta contínua;
- stream de eventos para inbox/thread em foreground/background;
- pipeline de comandos de envio com confirmação de resultado;
- push notifications operacionais por workspace.

Critérios:

- continuidade em background sem depender de WebView ativa no iPhone;
- reconexão e recuperação incremental por cursor;
- observabilidade ponta a ponta (latência, erro, fila, retries).

## Fase 5 - Hardening para Publicação App Store

Status: pendente.

- segurança, privacidade e revisão final de compliance;
- hardening de confiabilidade e performance em escala;
- testes E2E, chaos tests e plano de rollback;
- preparação de operação, suporte e documentação pública.
