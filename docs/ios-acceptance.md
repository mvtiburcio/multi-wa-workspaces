# Aceite — iOS Native UI (Planejamento v1)

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

- [ ] `WorkspaceSnapshot` cobre conectividade e estado operacional.
- [ ] `ConversationSummary` cobre dados mínimos de inbox.
- [ ] `ThreadMessage` cobre tipos e status de entrega.
- [ ] `SyncCursor` cobre recuperação incremental.
- [ ] `SendMessageCommand`/`SendMessageResult` cobrem idempotência e retorno.
- [ ] `RealtimeEvent` cobre atualização de workspace/inbox/thread.
- [ ] `FallbackRenderState` cobre política de degradação.

## Checklist de Produto/UX

- [ ] Jornada ponta a ponta documentada (QR -> inbox -> thread -> envio).
- [ ] Regras de navegação e estado por workspace definidas.
- [ ] Acessibilidade mínima definida (Dynamic Type, VoiceOver, contraste).
- [ ] Feedback operacional definido para erro, retry e fallback.

## Checklist de Risco/Operação

- [ ] Riscos de App Store/compliance registrados com mitigação.
- [ ] Riscos de mudança de frontend web com mitigação por fallback.
- [ ] Riscos de custo operacional de workers com estratégia de capacidade.
- [ ] SLOs iniciais de sync/render/envio definidos.

## Evidências desta Rodada

- [ ] `markdownlint` sem erros.
- [ ] revisão cruzada entre `roadmap`, `architecture`, `risks-and-limits` e `ios-prd` sem lacunas.
- [ ] ADR-0002 registrada e marcada como aceita.
