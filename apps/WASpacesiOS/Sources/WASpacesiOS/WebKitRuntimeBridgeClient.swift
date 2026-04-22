import Foundation
import WebKit
import WorkspaceApplicationServices
import WorkspaceBridgeClient
import WorkspaceBridgeContracts
import WorkspaceDomain

public enum WebKitRuntimeBridgeError: Error {
  case workspaceNotFound
  case webViewUnavailable
  case extractionFailed
  case serializationFailed
  case sendFailed(String)
}

public final class WebKitRuntimeBridgeClient: SessionBridgeClient, UpdatesProvider, CallsProvider, @unchecked Sendable {
  private let manager: WorkspaceManager
  private let stateStore = WebKitRuntimeStateStore()
  private let eventPollIntervalNanoseconds: UInt64 = 1_200_000_000

  public init(manager: WorkspaceManager) {
    self.manager = manager
  }

  public func fetchWorkspaceList() async throws -> [WorkspaceSnapshot] {
    await manager.refresh()

    if await MainActor.run(body: { manager.workspaces.isEmpty }) {
      _ = try await manager.create(name: "Workspace 1")
      await manager.refresh()
    }

    return await MainActor.run {
      manager.workspaces.map { workspace in
        WorkspaceSnapshot(
          id: workspace.id,
          name: workspace.name,
          connectivity: mapConnectivity(workspace.state),
          unreadTotal: manager.unreadByWorkspace[workspace.id] ?? 0,
          lastSyncAt: workspace.lastOpenedAt,
          workerState: workerState(for: workspace.state)
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }

  public func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceSnapshot {
    let created = try await manager.create(name: request.name)
    return WorkspaceSnapshot(
      id: created.id,
      name: created.name,
      connectivity: .cold,
      unreadTotal: 0,
      lastSyncAt: created.lastOpenedAt,
      workerState: .provisioning
    )
  }

  public func fetchSnapshot(for workspaceID: UUID) async throws -> BridgeEnvelope<SyncSnapshotPayload> {
    let extraction = try await extractWorkspaceData(workspaceID: workspaceID)
    let grouped = Dictionary(grouping: extraction.messages, by: { $0.conversationID })

    await stateStore.storeSupplementary(workspaceID: workspaceID, updates: extraction.updates, calls: extraction.calls)
    await stateStore.storeSnapshot(workspaceID: workspaceID, snapshot: extraction)

    let cursor = await stateStore.makeCursor(workspaceID: workspaceID, lastEventID: "snapshot-\(workspaceID.uuidString)")

    let payload = SyncSnapshotPayload(
      workspace: extraction.workspace,
      conversations: extraction.conversations,
      messages: grouped,
      cursor: cursor
    )

    return BridgeEnvelope(
      eventID: "snapshot-\(workspaceID.uuidString)",
      emittedAt: Date(),
      payload: payload
    )
  }

  public func events(for workspaceID: UUID) -> AsyncThrowingStream<BridgeEnvelope<SyncDeltaPayload>, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          _ = try await installMutationObserver(workspaceID: workspaceID)
          var previous = try await extractWorkspaceData(workspaceID: workspaceID)
          await stateStore.storeSnapshot(workspaceID: workspaceID, snapshot: previous)
          await stateStore.storeSupplementary(workspaceID: workspaceID, updates: previous.updates, calls: previous.calls)

          while !Task.isCancelled {
            try await Task.sleep(nanoseconds: eventPollIntervalNanoseconds)
            let current = try await extractWorkspaceData(workspaceID: workspaceID)

            let events = makeRealtimeEvents(previous: previous, current: current)
            let supplementaryChanged = previous.updates != current.updates || previous.calls != current.calls
            if events.isEmpty, !supplementaryChanged {
              previous = current
              continue
            }

            await stateStore.storeSnapshot(workspaceID: workspaceID, snapshot: current)
            await stateStore.storeSupplementary(workspaceID: workspaceID, updates: current.updates, calls: current.calls)

            let sequence = await stateStore.nextSequence(workspaceID: workspaceID)
            let eventID = "wk-\(workspaceID.uuidString)-\(sequence)"
            let cursor = SyncCursor(
              workspaceID: workspaceID,
              sequence: sequence,
              lastEventID: eventID,
              checkpointAt: Date()
            )
            let payload = SyncDeltaPayload(workspaceID: workspaceID, events: events, cursor: cursor)
            continuation.yield(BridgeEnvelope(eventID: eventID, emittedAt: Date(), payload: payload))

            previous = current
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  public func fetchQRCode(for workspaceID: UUID) async throws -> BridgeEnvelope<WorkspaceQRState> {
    let extraction = try await extractWorkspaceData(workspaceID: workspaceID)
    return BridgeEnvelope(
      eventID: "qr-\(workspaceID.uuidString)",
      emittedAt: Date(),
      payload: extraction.qrState
    )
  }

  public func send(_ command: SendMessageCommand) async throws -> SendMessageResult {
    let result = try await sendMessageViaWebView(command)
    return SendMessageResult(
      clientMessageID: command.clientMessageID,
      providerMessageID: result.providerMessageID,
      accepted: result.accepted,
      failureReason: result.failureReason,
      processedAt: Date()
    )
  }

  public func fetchUpdates(for workspaceID: UUID) async throws -> [UpdateItem] {
    let cached = await stateStore.updates(for: workspaceID)
    if !cached.isEmpty {
      return cached
    }

    let extraction = try await extractWorkspaceData(workspaceID: workspaceID)
    await stateStore.storeSupplementary(workspaceID: workspaceID, updates: extraction.updates, calls: extraction.calls)
    return extraction.updates
  }

  public func fetchCalls(for workspaceID: UUID) async throws -> [CallItem] {
    let cached = await stateStore.calls(for: workspaceID)
    if !cached.isEmpty {
      return cached
    }

    let extraction = try await extractWorkspaceData(workspaceID: workspaceID)
    await stateStore.storeSupplementary(workspaceID: workspaceID, updates: extraction.updates, calls: extraction.calls)
    return extraction.calls
  }

  @MainActor
  private func webView(for workspaceID: UUID) async throws -> WKWebView {
    try await manager.select(id: workspaceID)
    guard let selected = manager.selectedWebView else {
      throw WebKitRuntimeBridgeError.webViewUnavailable
    }
    return selected
  }

  private func extractWorkspaceData(workspaceID: UUID) async throws -> WebKitExtractedWorkspaceData {
    let selectedWorkspace = await MainActor.run {
      manager.workspaces.first(where: { $0.id == workspaceID })
    }

    guard let selectedWorkspace else {
      throw WebKitRuntimeBridgeError.workspaceNotFound
    }

    let webView = try await webView(for: workspaceID)
    let rawPayload = try await evaluateScript(script: Self.extractScript(workspaceID: workspaceID), in: webView)
    guard
      let data = rawPayload.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(WebKitExtractionPayload.self, from: data)
    else {
      throw WebKitRuntimeBridgeError.extractionFailed
    }

    return decoded.toContracts(
      workspace: selectedWorkspace,
      unreadTotal: await MainActor.run { manager.unreadByWorkspace[workspaceID] ?? 0 }
    )
  }

  private func installMutationObserver(workspaceID: UUID) async throws -> Bool {
    let webView = try await webView(for: workspaceID)
    let payload = try await evaluateScript(script: Self.observerScript, in: webView)
    return payload == "true"
  }

  private func sendMessageViaWebView(_ command: SendMessageCommand) async throws -> WebKitSendResultPayload {
    let webView = try await webView(for: command.workspaceID)
    let escapedConversationID = command.conversationID
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let escapedText = command.text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")

    let script = Self.sendScript(conversationID: escapedConversationID, text: escapedText)
    let payload = try await evaluateScript(script: script, in: webView)
    guard
      let data = payload.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(WebKitSendResultPayload.self, from: data)
    else {
      throw WebKitRuntimeBridgeError.serializationFailed
    }

    if !decoded.accepted {
      throw WebKitRuntimeBridgeError.sendFailed(decoded.failureReason ?? "send_failed")
    }

    return decoded
  }

  @MainActor
  private func evaluateScript(script: String, in webView: WKWebView) async throws -> String {
    let result = try await webView.evaluateJavaScript(script)
    if let text = result as? String {
      return text
    }
    if let bool = result as? Bool {
      return bool ? "true" : "false"
    }
    throw WebKitRuntimeBridgeError.serializationFailed
  }

  private func makeRealtimeEvents(previous: WebKitExtractedWorkspaceData, current: WebKitExtractedWorkspaceData) -> [RealtimeEvent] {
    var events: [RealtimeEvent] = []

    if previous.workspace != current.workspace {
      events.append(.workspaceUpdated(current.workspace))
    }

    let previousConversations = Dictionary(uniqueKeysWithValues: previous.conversations.map { ($0.id, $0) })
    for conversation in current.conversations {
      if previousConversations[conversation.id] != conversation {
        events.append(.conversationUpserted(conversation))
      }
    }

    let previousMessages = Dictionary(uniqueKeysWithValues: previous.messages.map { ($0.id, $0) })
    for message in current.messages {
      guard let previousMessage = previousMessages[message.id] else {
        events.append(.messageUpserted(message))
        continue
      }

      if previousMessage != message {
        events.append(.messageUpserted(message))
        if previousMessage.delivery != message.delivery {
          events.append(.messageStatusChanged(messageID: message.id, status: message.delivery))
        }
      }
    }

    return events
  }

  private func mapConnectivity(_ state: WorkspaceState) -> ConnectivityState {
    switch state {
    case .cold:
      return .cold
    case .loading:
      return .connecting
    case .qrRequired:
      return .qrRequired
    case .connected:
      return .connected
    case .disconnected:
      return .disconnected
    case .failed:
      return .degraded
    }
  }

  private func workerState(for state: WorkspaceState) -> WorkerState {
    switch state {
    case .cold:
      return .provisioning
    case .loading:
      return .retrying
    case .qrRequired:
      return .provisioning
    case .connected:
      return .running
    case .disconnected:
      return .retrying
    case .failed:
      return .failed
    }
  }

  private static let observerScript = #"""
    (() => {
      try {
        if (window.__waspacesObserverInstalled) {
          return 'true';
        }

        window.__waspacesMutationVersion = 0;
        const target = document.body;
        if (!target) {
          return 'false';
        }

        const observer = new MutationObserver(() => {
          window.__waspacesMutationVersion = (window.__waspacesMutationVersion || 0) + 1;
        });
        observer.observe(target, { childList: true, subtree: true, characterData: true });
        window.__waspacesObserverInstalled = true;
        return 'true';
      } catch (_) {
        return 'false';
      }
    })();
  """#

  private static func extractScript(workspaceID: UUID) -> String {
    #"""
      (() => {
        const now = Date.now();
        const defaultConversationPrefix = 'conv-\#(workspaceID.uuidString)-';

        const normalizeText = (value) => {
          if (!value) return '';
          return String(value).replace(/\s+/g, ' ').trim();
        };

        const safeQuery = (root, selector) => {
          try { return root.querySelector(selector); } catch (_) { return null; }
        };

        const safeQueryAll = (root, selector) => {
          try { return Array.from(root.querySelectorAll(selector)); } catch (_) { return []; }
        };

        const conversationRows = safeQueryAll(document, '#pane-side [role="listitem"]');
        const conversations = conversationRows.map((row, index) => {
          const titleNode = safeQuery(row, 'span[title]') || safeQuery(row, '[dir="auto"]');
          const previewNode = safeQuery(row, 'div[aria-label] span[dir="ltr"]') || safeQueryAll(row, 'span[dir="ltr"]').at(-1) || safeQuery(row, 'span[dir="auto"]');
          const badgeNode = safeQuery(row, 'span[aria-label*="unread"]') || safeQuery(row, '[data-testid="icon-unread-count"]') || safeQueryAll(row, 'span').find((el) => /^\d+$/.test(normalizeText(el.textContent)));
          const idNode = safeQuery(row, 'a[href*="/t/"]') || safeQuery(row, 'a');
          const avatarNode = safeQuery(row, 'img');

          const title = normalizeText(titleNode?.getAttribute('title') || titleNode?.textContent) || 'Conversa ' + (index + 1);
          const preview = normalizeText(previewNode?.textContent);
          const unreadRaw = normalizeText(badgeNode?.textContent);
          const unreadCount = Number.parseInt(unreadRaw, 10);

          let conversationID = row.getAttribute('data-id') || idNode?.getAttribute('data-id') || '';
          if (!conversationID && idNode?.getAttribute('href')) {
            const href = idNode.getAttribute('href');
            const match = href.match(/\/t\/([^/?#]+)/);
            if (match) {
              conversationID = match[1];
            }
          }
          if (!conversationID) {
            conversationID = defaultConversationPrefix + index;
          }

          return {
            id: conversationID,
            title,
            preview,
            unreadCount: Number.isFinite(unreadCount) ? unreadCount : 0,
            pinned: !!safeQuery(row, '[data-testid="pinned"]'),
            muted: !!safeQuery(row, '[data-testid="muted"]'),
            avatarURL: avatarNode?.getAttribute('src') || null,
            timestamp: now - (index * 1000)
          };
        });

        const activeChatID = (() => {
          const active = safeQuery(document, '#pane-side [role="listitem"][aria-selected="true"]');
          if (!active) return conversations[0]?.id || null;
          const activeID = active.getAttribute('data-id') || safeQuery(active, 'a[href*="/t/"]')?.getAttribute('href');
          if (!activeID) return conversations[0]?.id || null;
          const fromHref = (activeID.match(/\/t\/([^/?#]+)/) || [])[1];
          return fromHref || activeID;
        })();

        const messageRows = safeQueryAll(document, '#main [data-testid="msg-container"]');
        const messages = messageRows.map((row, index) => {
          const bubble = safeQuery(row, '.message-in, .message-out') || row;
          const textNodes = safeQueryAll(bubble, 'span.selectable-text span').map((n) => normalizeText(n.textContent)).filter(Boolean);
          const fallbackText = normalizeText(bubble.textContent);
          const messageText = textNodes.length ? textNodes.join(' ') : fallbackText;

          const classes = (bubble.className || '') + ' ' + (row.className || '');
          const direction = classes.includes('message-out') ? 'outgoing' : 'incoming';
          const messageID = bubble.getAttribute('data-id') || row.getAttribute('data-id') || `msg-${index}-${now}`;

          const ackNode = safeQuery(bubble, '[data-icon="msg-dblcheck"], [data-icon="msg-check"], [data-icon="msg-time"], [data-icon="msg-error"]');
          let delivery = 'delivered';
          if (direction === 'incoming') {
            delivery = 'read';
          } else if (ackNode?.getAttribute('data-icon')?.includes('msg-time')) {
            delivery = 'pending';
          } else if (ackNode?.getAttribute('data-icon')?.includes('msg-check')) {
            delivery = 'sent';
          } else if (ackNode?.getAttribute('data-icon')?.includes('msg-error')) {
            delivery = 'failed';
          }

          return {
            id: messageID,
            conversationID: activeChatID || conversations[0]?.id || defaultConversationPrefix + '0',
            direction,
            authorDisplayName: direction === 'incoming' ? (conversations[0]?.title || null) : 'Você',
            text: messageText,
            sentAt: now - ((messageRows.length - index) * 1000),
            delivery
          };
        }).filter((message) => message.text.length > 0);

        const updateRows = safeQueryAll(document, '[data-testid="status-list-item"], [data-testid="list-item-status-v3"], [data-testid="channels-list-item"]');
        const updates = updateRows.map((row, index) => {
          const title = normalizeText(safeQuery(row, '[dir="auto"]')?.textContent) || `Atualização ${index + 1}`;
          const subtitle = normalizeText(safeQueryAll(row, 'span').map((el) => normalizeText(el.textContent)).filter(Boolean).slice(-1)[0]) || 'Sem descrição';
          const unread = !!safeQuery(row, '[data-testid="unread-dot"]') || !!safeQuery(row, '[aria-label*="new"]');
          const kind = row.innerText.toLowerCase().includes('canal') ? 'channel' : 'status';
          return {
            id: row.getAttribute('data-id') || `upd-${index}-${now}`,
            title,
            subtitle,
            timestamp: now - (index * 60_000),
            kind,
            unread
          };
        });

        const callRows = safeQueryAll(document, '[data-testid="call-history-item"], [data-testid="calls-list-item"]');
        const calls = callRows.map((row, index) => {
          const textNodes = safeQueryAll(row, 'span').map((el) => normalizeText(el.textContent)).filter(Boolean);
          const contactName = textNodes[0] || `Contato ${index + 1}`;
          const details = textNodes.join(' ').toLowerCase();
          let direction = 'incoming';
          if (details.includes('perdida') || details.includes('missed')) {
            direction = 'missed';
          } else if (details.includes('saída') || details.includes('outgoing')) {
            direction = 'outgoing';
          }

          return {
            id: row.getAttribute('data-id') || `call-${index}-${now}`,
            contactName,
            occurredAt: now - (index * 120_000),
            durationSeconds: 0,
            direction
          };
        });

        const qrNode = safeQuery(document, '[data-testid="qrcode"]') || safeQuery(document, 'canvas[aria-label*="Scan"]') || safeQuery(document, 'canvas[aria-label*="Escaneie"]');
        const qrPayload = qrNode?.getAttribute('data-ref') || qrNode?.parentElement?.getAttribute('data-ref') || null;

        let connectionState = 'connected';
        if (qrNode) {
          connectionState = 'qrRequired';
        } else if (document.readyState === 'loading') {
          connectionState = 'connecting';
        } else if (!safeQuery(document, '#pane-side')) {
          connectionState = 'degraded';
        }

        return JSON.stringify({
          connectionState,
          qrPayload,
          qrExpired: document.body?.innerText?.toLowerCase().includes('expired') || false,
          conversations,
          messages,
          updates,
          calls,
          mutationVersion: window.__waspacesMutationVersion || 0
        });
      })();
    """#
  }

  private static func sendScript(conversationID: String, text: String) -> String {
    #"""
      (() => {
        const normalizeText = (value) => (value || '').replace(/\s+/g, ' ').trim();
        const conversationID = "\#(conversationID)";
        const text = "\#(text)";

        const rows = Array.from(document.querySelectorAll('#pane-side [role="listitem"]'));
        const targetRow = rows.find((row) => {
          const rowID = row.getAttribute('data-id') || row.querySelector('a[href*="/t/"]')?.getAttribute('href') || '';
          return rowID.includes(conversationID);
        });

        if (targetRow) {
          targetRow.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
          targetRow.click();
        }

        const composer = document.querySelector('footer [contenteditable="true"]') || document.querySelector('[contenteditable="true"][data-tab]');
        if (!composer) {
          return JSON.stringify({ accepted: false, failureReason: 'composer_not_found', providerMessageID: null });
        }

        composer.focus();
        try {
          document.execCommand('selectAll', false, null);
          document.execCommand('insertText', false, text);
        } catch (_) {
          composer.textContent = text;
        }
        composer.dispatchEvent(new InputEvent('input', { bubbles: true, data: text, inputType: 'insertText' }));

        const sendIcon = document.querySelector('span[data-icon="send"]');
        const sendButton = sendIcon ? sendIcon.closest('button') : null;
        if (sendButton) {
          sendButton.click();
        } else {
          composer.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', which: 13, keyCode: 13, bubbles: true }));
        }

        return JSON.stringify({
          accepted: true,
          failureReason: null,
          providerMessageID: `webkit-${Date.now()}`
        });
      })();
    """#
  }
}

private actor WebKitRuntimeStateStore {
  private var sequenceByWorkspace: [UUID: Int64] = [:]
  private var updatesByWorkspace: [UUID: [UpdateItem]] = [:]
  private var callsByWorkspace: [UUID: [CallItem]] = [:]
  private var latestSnapshotByWorkspace: [UUID: WebKitExtractedWorkspaceData] = [:]

  func nextSequence(workspaceID: UUID) -> Int64 {
    let next = (sequenceByWorkspace[workspaceID] ?? 0) + 1
    sequenceByWorkspace[workspaceID] = next
    return next
  }

  func makeCursor(workspaceID: UUID, lastEventID: String?) -> SyncCursor {
    let sequence = (sequenceByWorkspace[workspaceID] ?? 0) + 1
    sequenceByWorkspace[workspaceID] = sequence
    return SyncCursor(workspaceID: workspaceID, sequence: sequence, lastEventID: lastEventID, checkpointAt: Date())
  }

  func storeSupplementary(workspaceID: UUID, updates: [UpdateItem], calls: [CallItem]) {
    updatesByWorkspace[workspaceID] = updates
    callsByWorkspace[workspaceID] = calls
  }

  func updates(for workspaceID: UUID) -> [UpdateItem] {
    updatesByWorkspace[workspaceID] ?? []
  }

  func calls(for workspaceID: UUID) -> [CallItem] {
    callsByWorkspace[workspaceID] ?? []
  }

  func storeSnapshot(workspaceID: UUID, snapshot: WebKitExtractedWorkspaceData) {
    latestSnapshotByWorkspace[workspaceID] = snapshot
  }
}

private struct WebKitExtractedWorkspaceData: Hashable, Sendable {
  let workspace: WorkspaceSnapshot
  let conversations: [ConversationSummary]
  let messages: [ThreadMessage]
  let updates: [UpdateItem]
  let calls: [CallItem]
  let qrState: WorkspaceQRState
}

private struct WebKitExtractionPayload: Decodable {
  let connectionState: String
  let qrPayload: String?
  let qrExpired: Bool
  let conversations: [WebKitConversationPayload]
  let messages: [WebKitMessagePayload]
  let updates: [WebKitUpdatePayload]
  let calls: [WebKitCallPayload]
  let mutationVersion: Int64?

  func toContracts(workspace: Workspace, unreadTotal: Int) -> WebKitExtractedWorkspaceData {
    let now = Date()

    let connectivity = connectivityState(from: connectionState)
    let workerState: WorkerState = connectivity == .connected ? .running : .retrying

    let snapshot = WorkspaceSnapshot(
      id: workspace.id,
      name: workspace.name,
      connectivity: connectivity,
      unreadTotal: unreadTotal,
      lastSyncAt: now,
      workerState: workerState
    )

    let mappedConversations = conversations.enumerated().map { index, conversation in
      ConversationSummary(
        id: conversation.id,
        workspaceID: workspace.id,
        title: conversation.title,
        avatarURL: URL(string: conversation.avatarURL ?? ""),
        lastMessagePreview: conversation.preview,
        lastMessageAt: Date(timeIntervalSince1970: TimeInterval(conversation.timestamp) / 1000),
        unreadCount: conversation.unreadCount,
        pinRank: conversation.pinned ? index : nil,
        muteUntil: conversation.muted ? now.addingTimeInterval(24 * 3600) : nil,
        status: .active
      )
    }

    let mappedMessages = messages.map { message in
      ThreadMessage(
        id: message.id,
        workspaceID: workspace.id,
        conversationID: message.conversationID,
        direction: message.direction == "outgoing" ? .outgoing : .incoming,
        authorDisplayName: message.authorDisplayName,
        content: .text(message.text),
        sentAt: Date(timeIntervalSince1970: TimeInterval(message.sentAt) / 1000),
        delivery: deliveryStatus(from: message.delivery)
      )
    }

    let mappedUpdates = updates.map { update in
      UpdateItem(
        id: update.id,
        workspaceID: workspace.id,
        title: update.title,
        subtitle: update.subtitle,
        timestamp: Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000),
        kind: update.kind == "channel" ? .channel : .status,
        unread: update.unread
      )
    }

    let mappedCalls = calls.map { call in
      CallItem(
        id: call.id,
        workspaceID: workspace.id,
        contactName: call.contactName,
        occurredAt: Date(timeIntervalSince1970: TimeInterval(call.occurredAt) / 1000),
        durationSeconds: call.durationSeconds,
        direction: callDirection(from: call.direction)
      )
    }

    let qrState = WorkspaceQRState(
      workspaceID: workspace.id,
      state: qrConnectionState(connectivity: connectivity, expired: qrExpired),
      qrPayload: qrPayload ?? "QR_NOT_AVAILABLE",
      expiresAt: now.addingTimeInterval(60)
    )

    return WebKitExtractedWorkspaceData(
      workspace: snapshot,
      conversations: mappedConversations,
      messages: mappedMessages,
      updates: mappedUpdates,
      calls: mappedCalls,
      qrState: qrState
    )
  }

  private func connectivityState(from raw: String) -> ConnectivityState {
    switch raw {
    case "connecting":
      return .connecting
    case "qrRequired":
      return .qrRequired
    case "degraded":
      return .degraded
    case "disconnected":
      return .disconnected
    case "cold":
      return .cold
    default:
      return .connected
    }
  }

  private func qrConnectionState(connectivity: ConnectivityState, expired: Bool) -> QRConnectionState {
    if expired {
      return .expired
    }
    switch connectivity {
    case .qrRequired:
      return .pending
    case .connected:
      return .linked
    case .connecting:
      return .scanned
    default:
      return .pending
    }
  }

  private func deliveryStatus(from raw: String) -> DeliveryStatus {
    switch raw {
    case "pending":
      return .pending
    case "sent":
      return .sent
    case "read":
      return .read
    case "failed":
      return .failed
    default:
      return .delivered
    }
  }

  private func callDirection(from raw: String) -> CallDirection {
    switch raw {
    case "outgoing":
      return .outgoing
    case "missed":
      return .missed
    default:
      return .incoming
    }
  }
}

private struct WebKitConversationPayload: Decodable {
  let id: String
  let title: String
  let preview: String
  let unreadCount: Int
  let pinned: Bool
  let muted: Bool
  let avatarURL: String?
  let timestamp: Int64
}

private struct WebKitMessagePayload: Decodable {
  let id: String
  let conversationID: String
  let direction: String
  let authorDisplayName: String?
  let text: String
  let sentAt: Int64
  let delivery: String
}

private struct WebKitUpdatePayload: Decodable {
  let id: String
  let title: String
  let subtitle: String
  let timestamp: Int64
  let kind: String
  let unread: Bool
}

private struct WebKitCallPayload: Decodable {
  let id: String
  let contactName: String
  let occurredAt: Int64
  let durationSeconds: Int
  let direction: String
}

private struct WebKitSendResultPayload: Decodable {
  let accepted: Bool
  let failureReason: String?
  let providerMessageID: String?
}
