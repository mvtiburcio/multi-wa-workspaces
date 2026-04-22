# Session Bridge — Especificação Operacional Mínima (Sprint 1 -> Sprint 2)

## Objetivo
Definir o contrato operacional para implementação do Session Bridge Cloud no Sprint 2, mantendo o app iOS Sprint 1 compatível desde já.

## Endpoints-alvo

### `POST /v1/workspaces/{workspaceID}/sync`
Entrada:
- `schemaVersion` (int)
- `cursor` (`SyncCursor?`)

Saída:
- envelope `BridgeEnvelope<SyncSnapshotPayload>` quando `cursor` ausente;
- envelope `BridgeEnvelope<SyncDeltaPayload>` quando `cursor` presente.

### `GET /v1/workspaces/{workspaceID}/events`
Saída:
- stream de envelopes `BridgeEnvelope<SyncDeltaPayload>` com `RealtimeEvent[]`.

### `POST /v1/workspaces/{workspaceID}/messages/send`
Entrada:
- `SendMessageCommand`.

Saída:
- `SendMessageResult`.

### `POST /v1/workspaces`
Entrada:
- `CreateWorkspaceRequest`.

Saída:
- `WorkspaceSnapshot` inicial com estado `qrRequired`.

### `GET /v1/workspaces/{workspaceID}/notifications`
Saída:
- fila interna de payloads de notificação (`NotificationQueueItem`) para operação interna (sem APNs nesta entrega).

## Provider de sessão real (WAHA)

Quando habilitado (`WASPACES_BRIDGE_WAHA_ENABLED=1`), a bridge passa a usar WAHA como provider real de sessão por workspace:

- provisionamento de sessão por workspace no `POST /v1/workspaces`;
- refresh de chats/mensagens no `POST /sync`;
- QR real no `GET /qr`;
- envio real no `POST /messages/send`.

Variáveis:

- `WASPACES_WAHA_BASE_URL`
- `WASPACES_WAHA_API_KEY` (opcional conforme deploy)
- `WASPACES_WAHA_SESSION_PREFIX` (default: `ws`)
- `WASPACES_WAHA_FORCE_DEFAULT_SESSION` (quando `1`, usa sessão única `default`; útil para WAHA Core)

## Envelope e versionamento

- `schemaVersion` obrigatório em payloads de sync/evento/erro;
- versão inicial: `1`;
- mudanças breaking exigem incremento de versão e suporte dual em rollout.

## Erros padronizados

- formato: `BridgeErrorEnvelope`;
- códigos iniciais: `unauthorized`, `workspaceNotFound`, `rateLimited`, `transientNetwork`, `parserDegraded`, `internalError`;
- `retryAfterMilliseconds` opcional para controle de backoff no cliente.

## Idempotência de envio

- chave idempotente: `clientMessageID` do `SendMessageCommand`;
- duplicidade deve retornar o mesmo `SendMessageResult` previamente confirmado;
- armazenamento de deduplicação por workspace com TTL operacional.

## Retry/Backoff recomendado

- estratégia inicial: exponencial;
- `initialDelayMilliseconds`: 500;
- `maxDelayMilliseconds`: 10_000;
- `maxAttempts`: 5;
- operações de envio devem interromper retries para erros de validação semântica.

Status atual:
- implementado no client HTTP do app (`WASPACES_BRIDGE_RETRY_*`).

## Observabilidade mínima

Campos obrigatórios de log estruturado:
- `workspace_id`
- `event`
- `schema_version`
- `duration_ms`
- `result`
- `error_code` (quando houver)

Métricas obrigatórias:
- latência `sync` p95;
- latência de ACK local/resultado de envio;
- backlog de stream/eventos;
- taxa de `fallback` por workspace.
