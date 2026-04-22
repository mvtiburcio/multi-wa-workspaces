# Aceite — iOS Native UI (Implementação internal-only)

## Critério de Pronto da Rodada de Planejamento

- documentação principal alinhada com `iPhone-first`;
- gate obrigatório de App Store explícito antes da codificação;
- arquitetura em dois planos (App iOS + Session Bridge Cloud) documentada;
- contratos de dados e fallback híbrido definidos;
- ausência de contradições entre roadmap, arquitetura, riscos e PRD.

## Cenários Obrigatórios de Aceite Funcional (para implementação)

1. Onboarding de workspace com QR e sincronização inicial concluída.
2. Inbox nativa atualizando em tempo real após eventos de bridge.
3. Thread nativa com envio e atualização de status de entrega.
4. Alternância entre workspaces sem vazamento de sessão/dados.
5. App em background mantendo continuidade via bridge cloud + push.
6. Falha de parsing acionando fallback híbrido controlado (WebView).

## Checklist Técnico

- [x] `WorkspaceSnapshot` cobre conectividade e estado operacional.
- [x] `ConversationSummary` cobre dados mínimos de inbox.
- [x] `ThreadMessage` cobre tipos e status de entrega.
- [x] `SyncCursor` cobre recuperação incremental.
- [x] `SendMessageCommand`/`SendMessageResult` cobrem idempotência e retorno.
- [x] `RealtimeEvent` cobre atualização de workspace/inbox/thread.
- [x] `FallbackRenderState` cobre política de degradação.

## Checklist de Produto/UX

- [x] Jornada ponta a ponta documentada (QR -> inbox -> thread -> envio).
- [x] Regras de navegação e estado por workspace definidas.
- [x] Acessibilidade mínima definida (Dynamic Type, VoiceOver, contraste).
- [x] Feedback operacional definido para erro, retry e fallback.

## Checklist de Risco/Operação

- [x] Riscos de App Store/compliance registrados com mitigação.
- [x] Riscos de mudança de frontend web com mitigação por fallback.
- [x] Riscos de custo operacional de workers com estratégia de capacidade.
- [x] SLOs iniciais de sync/render/envio definidos.

## Evidências desta Rodada

- [x] revisão cruzada entre `roadmap`, `architecture`, `risks-and-limits` e `ios-prd` sem lacunas.
- [x] ADR-0002 registrada e marcada como aceita.
- [x] suíte de build/test verde (`swift build`, `swift test`) com bridge + iOS.
- [x] app iOS instalado e lançado no simulador (`simctl install` + `simctl launch`) em tema escuro.
- [x] app iOS operando em runtime WebKit com sessão real de `web.whatsapp.com` e isolamento por workspace.
- [x] criação de workspace em fluxo real via `POST /v1/workspaces` com snapshot funcional.
- [x] erro de API padronizado em `BridgeErrorEnvelope` validado por teste de `401`.
- [x] retry/backoff no client bridge configurável por ambiente (`WASPACES_BRIDGE_RETRY_*`).
- [x] pipeline interno de notificações na bridge (`/notifications`) com payload estruturado.
- [ ] `markdownlint` sem erros (pendente de execução no CI de docs).

## Pendências para fechamento de release pública

- [ ] gate formal App Store (`go/no-go`) assinado por produto/engenharia/compliance.
- [x] worker/provider real opcional implementado via WAHA (`WASPACES_BRIDGE_WAHA_ENABLED=1`) com QR/sync/send por workspace.
- [ ] operação multi-workspace 100% real exige provider com suporte a múltiplas sessões simultâneas (ex.: WAHA Plus); WAHA Core opera em sessão única `default`.
- [ ] push pipeline operacional (APNs) conectado ao stream da bridge.
