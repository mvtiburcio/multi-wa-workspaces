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

## Fase 3 - iOS Full Native (iPhone-first + WebKit Runtime)

Status: em andamento (Sprint 2 internal-only, trilha funcional base concluída).

Escopo funcional v1:

- onboarding por QR para vínculo de workspace;
- inbox nativa completa com busca, filtros e estados;
- thread nativa completa com composer, envio e status de entrega;
- alternância de workspace sem vazamento;
- cache local e sincronização incremental.

Regras desta fase:

- UI/UX 100% nativa iOS com render de sessão real via WebKit;
- isolamento estrito por workspace no mesmo modelo da trilha macOS;
- fallback híbrido controlado quando parser/bridge estiver indisponível.
- sem `go` formal de compliance, build iOS não segue para distribuição pública.

Entregas já concluídas nesta fase:

- shell iOS nativo com abas `Chats`, `Atualizações`, `Chamadas`, `Ajustes`;
- `Chats` conectado ao runtime WebKit real (`web.whatsapp.com`) com switcher de workspace;
- app iOS iniciando pela UI nativa (`IOSRootView`) com providers reais WebKit (sem mock em runtime normal);
- fluxo `Workspace -> Inbox -> Thread -> Envio` com estados `pending/sent/failed`;
- busca e filtro de não lidas em `Chats`;
- switcher de workspace com QR e criação de novo workspace via bridge (`POST /v1/workspaces`);
- isolamento por `workspaceID` preservado entre abas e fallback manual por workspace;
- app instalável em simulador (`simctl install` + `simctl launch`) com validação em tema escuro.

## Fase 4 - Session Bridge Cloud (tempo real contínuo)

Status: em andamento (MVP local implementado).

Escopo:

- worker dedicado por workspace para manter sessão e coleta contínua;
- stream de eventos para inbox/thread em foreground/background;
- pipeline de comandos de envio com confirmação de resultado;
- push notifications operacionais por workspace.

Critérios:

- continuidade em background sem depender de WebView ativa no iPhone;
- reconexão e recuperação incremental por cursor;
- observabilidade ponta a ponta (latência, erro, fila, retries).

Entregas já concluídas nesta fase:

- endpoints reais `workspaces`, `sync`, `events` (SSE), `send`, `qr`, `updates`, `calls`, `notifications`;
- autenticação Bearer + persistência SQLite + idempotência por `clientMessageID`;
- erros padronizados em `BridgeErrorEnvelope` (incluindo `unauthorized` e `workspaceNotFound`);
- retry/backoff configurável no client iOS (`WASPACES_BRIDGE_RETRY_*`);
- fila interna de notificação estruturada por workspace (sem APNs externo nesta entrega);
- integração opcional com provider real WAHA para QR/sync/send por workspace;
- runtime iOS com provider primário WebKit Session (WAHA permanece apenas opcional por feature flag no bridge);
- contrato compartilhado único entre app iOS e bridge;
- cobertura de testes para endpoints principais.

## Fase 5 - Hardening para Publicação App Store

Status: pendente.

- segurança, privacidade e revisão final de compliance;
- hardening de confiabilidade e performance em escala;
- testes E2E, chaos tests e plano de rollback;
- preparação de operação, suporte e documentação pública.
