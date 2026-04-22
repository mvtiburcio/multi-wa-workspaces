# Plano Técnico — iOS Native UI (v1)

## Objetivo

Definir o plano técnico para entregar um app iOS com interface nativa completa para múltiplos workspaces, mantendo tempo real contínuo por meio de Session Bridge Cloud.

## Escopo Funcional Completo (v1)

- onboarding de workspace por QR;
- inbox nativa (lista de conversas, unread, última mensagem, timestamp, status);
- thread nativa (histórico, tipos de mensagem, estados de envio/entrega/leitura);
- composer com envio de mensagens textuais e feedback operacional;
- alternância de workspace sem vazamento de contexto;
- sincronização incremental com recuperação após reconexão.

## Arquitetura Técnica

### App iOS

- SwiftUI como camada de apresentação;
- armazenamento local para snapshot, threads e cursor;
- cliente de sync/realtime para aplicar deltas;
- orchestrator de fallback híbrido para cenários de falha de parser.

### Session Bridge Cloud

- worker por workspace para manter sessão ativa e parsear dados;
- normalização em contratos internos estáveis;
- API de sync (snapshot + delta);
- stream de eventos em tempo real;
- pipeline de envio com confirmação de resultado.

## Contratos de Planejamento (Draft)

```swift
public struct WorkspaceSnapshot: Identifiable, Hashable, Codable {
  public let id: UUID
  public let name: String
  public let connectivity: ConnectivityState
  public let unreadTotal: Int
  public let lastSyncAt: Date?
  public let workerState: WorkerState
}

public enum ConnectivityState: String, Codable {
  case cold
  case connecting
  case qrRequired
  case connected
  case degraded
  case disconnected
}

public enum WorkerState: String, Codable {
  case provisioning
  case running
  case retrying
  case paused
  case failed
}
```

```swift
public struct ConversationSummary: Identifiable, Hashable, Codable {
  public let id: String
  public let workspaceID: UUID
  public let title: String
  public let avatarURL: URL?
  public let lastMessagePreview: String
  public let lastMessageAt: Date?
  public let unreadCount: Int
  public let pinRank: Int?
  public let muteUntil: Date?
  public let status: ConversationStatus
}

public enum ConversationStatus: String, Codable {
  case active
  case archived
  case muted
  case blocked
}
```

```swift
public struct ThreadMessage: Identifiable, Hashable, Codable {
  public let id: String
  public let workspaceID: UUID
  public let conversationID: String
  public let direction: MessageDirection
  public let authorDisplayName: String?
  public let content: MessageContent
  public let sentAt: Date
  public let delivery: DeliveryStatus
}

public enum MessageDirection: String, Codable { case incoming, outgoing }

public enum DeliveryStatus: String, Codable {
  case pending
  case sent
  case delivered
  case read
  case failed
}

public enum MessageContent: Hashable, Codable {
  case text(String)
  case media(url: URL, caption: String?)
  case system(String)
}
```

```swift
public struct SyncCursor: Hashable, Codable {
  public let workspaceID: UUID
  public let sequence: Int64
  public let lastEventID: String?
  public let checkpointAt: Date
}
```

```swift
public struct SendMessageCommand: Hashable, Codable {
  public let workspaceID: UUID
  public let conversationID: String
  public let clientMessageID: UUID
  public let text: String
  public let requestedAt: Date
}

public struct SendMessageResult: Hashable, Codable {
  public let clientMessageID: UUID
  public let providerMessageID: String?
  public let accepted: Bool
  public let failureReason: String?
  public let processedAt: Date
}
```

```swift
public enum RealtimeEvent: Hashable, Codable {
  case workspaceUpdated(WorkspaceSnapshot)
  case conversationUpserted(ConversationSummary)
  case messageUpserted(ThreadMessage)
  case messageStatusChanged(messageID: String, status: DeliveryStatus)
  case syncCheckpoint(SyncCursor)
}

public enum FallbackRenderState: Hashable, Codable {
  case native
  case degraded(reason: String)
  case webViewFallback(reason: String, startedAt: Date)
  case recovering
}
```

## Ciclo de Vida do Worker por Workspace

1. `provisioning`: aloca recursos e valida sessão.
2. `running`: coleta, normaliza e publica eventos.
3. `retrying`: falha transitória com retry/backoff.
4. `paused`: intervenção operacional controlada.
5. `failed`: erro não recuperável, exige ação de manutenção.

Regras:

- segregação rígida por `workspaceID`;
- idempotência em comandos de envio;
- checkpoints de cursor para replay seguro.

## Estratégia de Fallback Híbrido

Gatilhos de fallback:

- parser quebrado por mudança estrutural de frontend;
- lacuna de dados críticos para inbox/thread;
- erro contínuo acima do orçamento de falha.

Política:

- manter UI nativa como padrão;
- abrir WebView controlada apenas para o workspace afetado;
- registrar `FallbackRenderState` e telemetria de degradação;
- sair do fallback automaticamente quando parser normalizar.

## Segurança

- autenticação forte entre app e bridge;
- segregação de dados por workspace e usuário local;
- criptografia em trânsito e em repouso;
- trilha de auditoria para comandos de envio;
- política de minimização de dados no cliente.

## Observabilidade

Métricas obrigatórias:

- latência de ingestão de evento por workspace;
- tempo de render de inbox/thread;
- taxa de erro de envio;
- backlog de fila de eventos/comandos;
- frequência e duração de fallback híbrido.

Logs estruturados mínimos:

- `workspace_id`
- `event`
- `duration_ms`
- `result`
- `fallback_state`

## SLOs Iniciais

- sync incremental (`worker -> app`) p95 <= 3s;
- render inicial de inbox p95 <= 700ms após snapshot local;
- troca de workspace aquecido p95 <= 300ms;
- ACK de envio local p95 <= 200ms;
- confirmação de envio (`accepted`) p95 <= 5s em condição nominal.

## Fora de Escopo desta Fase de Planejamento

- implementação Swift e infraestrutura cloud;
- publicação App Store sem gate de conformidade concluído;
- suporte oficial a outras plataformas além de iPhone no v1.
