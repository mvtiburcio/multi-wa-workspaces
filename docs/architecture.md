# Arquitetura

## Visão Geral

A arquitetura evolui para dois planos complementares:

1. Plano App iOS (`iPhone-first`): interface nativa, cache local, sincronização incremental e renderização de inbox/thread/composer.
2. Plano Cloud (`Session Bridge`): worker por workspace, extração/normalização dos dados, distribuição de eventos em tempo real e execução de comandos de envio.

O app iOS não depende de renderização contínua de WebView para experiência principal. A WebView entra apenas em modo de fallback controlado.

## Plano App iOS

Camadas:

1. `Presentation` (SwiftUI): inbox, thread, composer, settings e estados operacionais.
2. `Application` (use cases): seleção de workspace, sync, envio, fallback, observabilidade.
3. `Data` (local): armazenamento de snapshot, threads, cursores e preferências.
4. `Realtime Client`: assinatura de eventos e reconexão resiliente.

Responsabilidades:

- manter estado local consistente por workspace;
- aplicar eventos incrementais em foreground/background;
- expor experiência nativa fluida para leitura e envio.

## Plano Cloud (Session Bridge)

Componentes:

1. `Workspace Worker`: mantém sessão ativa por workspace e executa parsing/normalização.
2. `Event Stream`: distribui `RealtimeEvent` para clientes conectados e pipeline de push.
3. `Command API`: recebe `SendMessageCommand`, valida e encaminha execução.
4. `Sync API`: entrega snapshots e deltas baseados em `SyncCursor`.
5. `Observability`: métricas, tracing, auditoria e alarmes operacionais.

Responsabilidades:

- continuidade de sessão em tempo real fora do ciclo de vida do iOS;
- consistência eventual com recuperação por cursor;
- segurança de transporte e segregação por workspace.

## Fluxo Resumido de Dados

1. Worker processa estado do workspace e gera eventos normalizados.
2. Eventos entram no stream e são consumidos pelo app iOS.
3. App aplica deltas em cache local e atualiza UI nativa.
4. Envio no composer gera `SendMessageCommand`.
5. Cloud executa comando e responde com `SendMessageResult` + eventos de status.

## Contratos de Planejamento (alto nível)

- `WorkspaceSnapshot`
- `ConversationSummary`
- `ThreadMessage`
- `SyncCursor`
- `SendMessageCommand` / `SendMessageResult`
- `RealtimeEvent`
- `FallbackRenderState`

Os contratos detalhados estão em [`technical-plan-ios-native-ui.md`](./technical-plan-ios-native-ui.md).

## Princípios Arquiteturais

- UI nativa como caminho primário;
- isolamento por workspace em toda a cadeia;
- observabilidade e operação desde v1;
- fallback híbrido obrigatório para resiliência;
- hardening orientado a publicação App Store.
