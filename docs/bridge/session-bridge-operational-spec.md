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
