import SwiftUI
import WorkspaceBridgeContracts
#if os(iOS)
import SafariServices
import CoreImage.CIFilterBuiltins
#endif

private var leadingToolbarPlacement: ToolbarItemPlacement {
  #if os(iOS)
  return .topBarLeading
  #else
  return .automatic
  #endif
}

private var trailingToolbarPlacement: ToolbarItemPlacement {
  #if os(iOS)
  return .topBarTrailing
  #else
  return .automatic
  #endif
}

private var threadBackgroundColor: Color {
  #if os(iOS)
  return Color(uiColor: .systemBackground)
  #else
  return Color.black.opacity(0.05)
  #endif
}

struct IOSRootView: View {
  enum MainTab: Hashable {
    case chats
    case updates
    case calls
    case settings
  }

  @ObservedObject var viewModel: IOSAppViewModel
  @State private var selectedTab: MainTab = .chats
  @State private var isWorkspaceSwitcherPresented = false

  var body: some View {
    TabView(selection: $selectedTab) {
      ChatsRootView(viewModel: viewModel, isWorkspaceSwitcherPresented: $isWorkspaceSwitcherPresented)
        .tabItem {
          Label("Chats", systemImage: "message")
        }
        .tag(MainTab.chats)

      UpdatesRootView(viewModel: viewModel, isWorkspaceSwitcherPresented: $isWorkspaceSwitcherPresented)
        .tabItem {
          Label("Atualizações", systemImage: "circle.dashed.inset.filled")
        }
        .tag(MainTab.updates)

      CallsRootView(viewModel: viewModel, isWorkspaceSwitcherPresented: $isWorkspaceSwitcherPresented)
        .tabItem {
          Label("Chamadas", systemImage: "phone")
        }
        .tag(MainTab.calls)

      SettingsRootView(viewModel: viewModel, isWorkspaceSwitcherPresented: $isWorkspaceSwitcherPresented)
        .tabItem {
          Label("Ajustes", systemImage: "gearshape")
        }
        .tag(MainTab.settings)
    }
    .sheet(isPresented: $isWorkspaceSwitcherPresented) {
      WorkspaceSwitcherSheet(viewModel: viewModel)
        .presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $viewModel.isFallbackWebPresented) {
      if let fallbackWebURL = viewModel.fallbackWebURL {
        FallbackWebView(url: fallbackWebURL)
      }
    }
    .task {
      await viewModel.bootstrap()
    }
  }
}

private struct ChatsRoute: Hashable {
  let conversationID: String
}

private struct ChatsRootView: View {
  @ObservedObject var viewModel: IOSAppViewModel
  @Binding var isWorkspaceSwitcherPresented: Bool

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isBootstrapping {
          ProgressView("Carregando conversas...")
        } else if let bootstrapErrorMessage = viewModel.bootstrapErrorMessage {
          ContentUnavailableView(
            "Falha ao carregar",
            systemImage: "wifi.slash",
            description: Text(bootstrapErrorMessage)
          )
          .padding()
        } else if viewModel.conversations.isEmpty {
          ContentUnavailableView(
            "Sem conversas",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Conecte um workspace via QR para iniciar.")
          )
          .padding()
        } else if viewModel.filteredConversations.isEmpty {
          ContentUnavailableView.search(text: viewModel.chatsSearchText)
            .padding()
        } else {
          List(viewModel.filteredConversations) { conversation in
            NavigationLink(value: ChatsRoute(conversationID: conversation.id)) {
              ConversationRow(conversation: conversation)
            }
            .listRowSeparator(.visible)
          }
          .listStyle(.plain)
        }
      }
      .searchable(text: $viewModel.chatsSearchText, prompt: "Buscar chats")
      .navigationTitle("Chats")
      .navigationDestination(for: ChatsRoute.self) { route in
        ThreadScreen(viewModel: viewModel, conversationID: route.conversationID)
      }
      .toolbar {
        WorkspaceSwitcherToolbarItem(
          workspace: viewModel.selectedWorkspace,
          action: { isWorkspaceSwitcherPresented = true }
        )

        ToolbarItem(placement: trailingToolbarPlacement) {
          HStack(spacing: 10) {
            Button {
              viewModel.showUnreadOnly.toggle()
            } label: {
              Image(systemName: viewModel.showUnreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filtrar não lidas")

            Button {
              Task {
                await viewModel.simulateFallbackDegradation()
              }
            } label: {
              Image(systemName: "exclamationmark.triangle")
            }
            .accessibilityLabel("Simular degradação")
          }
        }
      }
    }
  }
}

private struct UpdatesRootView: View {
  @ObservedObject var viewModel: IOSAppViewModel
  @Binding var isWorkspaceSwitcherPresented: Bool

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isUpdatesLoading {
          ProgressView("Carregando atualizações...")
        } else if viewModel.updates.isEmpty {
          ContentUnavailableView(
            "Sem atualizações",
            systemImage: "circle.dotted",
            description: Text("Sem dados recentes para o workspace selecionado.")
          )
        } else {
          List(viewModel.updates) { item in
            UpdateRow(item: item)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Atualizações")
      .toolbar {
        WorkspaceSwitcherToolbarItem(
          workspace: viewModel.selectedWorkspace,
          action: { isWorkspaceSwitcherPresented = true }
        )
      }
    }
  }
}

private struct CallsRootView: View {
  @ObservedObject var viewModel: IOSAppViewModel
  @Binding var isWorkspaceSwitcherPresented: Bool

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.isCallsLoading {
          ProgressView("Carregando chamadas...")
        } else if viewModel.calls.isEmpty {
          ContentUnavailableView(
            "Sem chamadas",
            systemImage: "phone.arrow.up.right",
            description: Text("Sem chamadas registradas para o workspace selecionado.")
          )
        } else {
          List(viewModel.calls) { item in
            CallRow(item: item)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Chamadas")
      .toolbar {
        WorkspaceSwitcherToolbarItem(
          workspace: viewModel.selectedWorkspace,
          action: { isWorkspaceSwitcherPresented = true }
        )
      }
    }
  }
}

private struct SettingsRootView: View {
  @ObservedObject var viewModel: IOSAppViewModel
  @Binding var isWorkspaceSwitcherPresented: Bool

  var body: some View {
    NavigationStack {
      List {
        Section("Workspace ativo") {
          if let workspace = viewModel.selectedWorkspace {
            HStack(spacing: 12) {
              Circle()
                .fill(connectivityColor(workspace.connectivity))
                .frame(width: 12, height: 12)
              VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name)
                  .font(.headline)
                Text(connectivityLabel(workspace.connectivity))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } else {
            Text("Nenhum workspace selecionado")
          }

          Button("Trocar workspace") {
            isWorkspaceSwitcherPresented = true
          }
        }

        Section("Conexão") {
          Label(
            "Session Bridge ativa",
            systemImage: "antenna.radiowaves.left.and.right"
          )
        }

        Section("Gate de release") {
          Text("Build iOS permanece internal-only até gate App Store formal.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Ajustes")
      .toolbar {
        WorkspaceSwitcherToolbarItem(
          workspace: viewModel.selectedWorkspace,
          action: { isWorkspaceSwitcherPresented = true }
        )
      }
    }
  }

  private func connectivityLabel(_ state: ConnectivityState) -> String {
    switch state {
    case .cold:
      return "Frio"
    case .connecting:
      return "Conectando"
    case .qrRequired:
      return "QR necessário"
    case .connected:
      return "Conectado"
    case .degraded:
      return "Degradado"
    case .disconnected:
      return "Desconectado"
    }
  }

  private func connectivityColor(_ state: ConnectivityState) -> Color {
    switch state {
    case .connected:
      return .green
    case .connecting, .qrRequired:
      return .orange
    case .degraded:
      return .yellow
    case .disconnected, .cold:
      return .gray
    }
  }
}

private struct ThreadScreen: View {
  @ObservedObject var viewModel: IOSAppViewModel
  let conversationID: String

  var body: some View {
    VStack(spacing: 0) {
      FallbackBanner(state: viewModel.fallbackState) {
        viewModel.openFallbackWebForCurrentWorkspace()
      } recoverAction: {
        Task {
          await viewModel.recoverFallback()
        }
      }

      List(viewModel.messages) { message in
        ThreadRow(message: message)
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }
      .listStyle(.plain)
      .background(threadBackgroundColor)

      ComposerBar(
        text: $viewModel.composerText,
        onSend: {
          Task {
            await viewModel.sendCurrentMessage()
          }
        }
      )
    }
    .navigationTitle("Conversa")
    .task(id: conversationID) {
      viewModel.selectConversation(id: conversationID)
    }
  }
}

private struct WorkspaceSwitcherToolbarItem: ToolbarContent {
  let workspace: WorkspaceSnapshot?
  let action: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: leadingToolbarPlacement) {
      Button(action: action) {
        HStack(spacing: 8) {
          Circle()
            .fill(workspace.map { connectivityColor($0.connectivity) } ?? .gray)
            .frame(width: 28, height: 28)
            .overlay(
              Text(workspaceInitial)
                .font(.caption.bold())
                .foregroundStyle(.white)
            )
          Text(workspace?.name ?? "Workspace")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }
      }
      .accessibilityLabel("Selecionar workspace")
    }
  }

  private var workspaceInitial: String {
    String((workspace?.name ?? "W").prefix(1)).uppercased()
  }

  private func connectivityColor(_ state: ConnectivityState) -> Color {
    switch state {
    case .connected:
      return .green
    case .connecting, .qrRequired:
      return .orange
    case .degraded:
      return .yellow
    case .disconnected, .cold:
      return .gray
    }
  }
}

private struct WorkspaceSwitcherSheet: View {
  @ObservedObject var viewModel: IOSAppViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var newWorkspaceName = ""

  var body: some View {
    NavigationStack {
      List {
        Section("Workspaces") {
          ForEach(viewModel.workspaces) { workspace in
            Button {
              Task {
                try? await viewModel.selectWorkspace(id: workspace.id)
                dismiss()
              }
            } label: {
              WorkspaceSelectionRow(
                workspace: workspace,
                isSelected: viewModel.selectedWorkspaceID == workspace.id,
                connectivityLabel: connectivityLabel(workspace.connectivity),
                connectivityColor: connectivityColor(workspace.connectivity)
              )
            }
            .buttonStyle(.plain)
          }
        }

        Section("Conexão por QR") {
          if let qrState = viewModel.qrState {
            VStack(alignment: .leading, spacing: 8) {
              Text("Estado: \(qrLabel(qrState.state))")
                .font(.subheadline.weight(.semibold))
              QRCodeCard(payload: qrState.qrPayload)
              Text("Expira em \(qrState.expiresAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } else {
            Text("QR indisponível para o workspace atual.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Button("Atualizar QR") {
            Task {
              await viewModel.reloadQRCodeForSelectedWorkspace()
            }
          }
        }

        Section("Novo workspace") {
          TextField("Nome do workspace", text: $newWorkspaceName)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            .autocorrectionDisabled()

          Button {
            Task {
              let created = await viewModel.createWorkspace(named: newWorkspaceName)
              if created {
                newWorkspaceName = ""
                dismiss()
              }
            }
          } label: {
            if viewModel.isCreatingWorkspace {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Text("Criar e conectar via QR")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(viewModel.isCreatingWorkspace || newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .navigationTitle("Selecionar workspace")
      .toolbar {
        ToolbarItem(placement: trailingToolbarPlacement) {
          Button("Fechar") {
            dismiss()
          }
        }
      }
    }
  }

  private func qrLabel(_ state: QRConnectionState) -> String {
    switch state {
    case .pending:
      return "Aguardando leitura"
    case .scanned:
      return "Escaneado"
    case .linked:
      return "Conectado"
    case .expired:
      return "Expirado"
    }
  }

  private func connectivityColor(_ state: ConnectivityState) -> Color {
    switch state {
    case .connected:
      return .green
    case .connecting, .qrRequired:
      return .orange
    case .degraded:
      return .yellow
    case .disconnected, .cold:
      return .gray
    }
  }

  private func connectivityLabel(_ state: ConnectivityState) -> String {
    switch state {
    case .cold:
      return "Frio"
    case .connecting:
      return "Conectando"
    case .qrRequired:
      return "QR necessário"
    case .connected:
      return "Conectado"
    case .degraded:
      return "Degradado"
    case .disconnected:
      return "Desconectado"
    }
  }
}

private struct QRCodeCard: View {
  let payload: String

  var body: some View {
    #if os(iOS)
    VStack(alignment: .leading, spacing: 8) {
      if let image = qrImage(from: payload) {
        Image(uiImage: image)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .frame(height: 220)
          .padding(8)
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color.white)
          )
      } else {
        Text("Não foi possível gerar o QR para este payload.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(payload)
        .font(.caption2.monospaced())
        .lineLimit(2)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
    #else
    Text(payload)
      .font(.caption2.monospaced())
      .lineLimit(2)
      .truncationMode(.middle)
    #endif
  }

  #if os(iOS)
  private let context = CIContext()
  private let filter = CIFilter.qrCodeGenerator()

  private func qrImage(from raw: String) -> UIImage? {
    let data = Data(raw.utf8)
    filter.setValue(data, forKey: "inputMessage")
    filter.correctionLevel = "M"
    guard let outputImage = filter.outputImage else {
      return nil
    }

    let transform = CGAffineTransform(scaleX: 12, y: 12)
    let scaled = outputImage.transformed(by: transform)
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }
  #endif
}

private struct WorkspaceSelectionRow: View {
  let workspace: WorkspaceSnapshot
  let isSelected: Bool
  let connectivityLabel: String
  let connectivityColor: Color

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(connectivityColor)
        .frame(width: 38, height: 38)
        .overlay(
          Text(String(workspace.name.prefix(1)).uppercased())
            .font(.headline)
            .foregroundStyle(.white)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text(workspace.name)
          .font(.headline)
        Text(connectivityLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if workspace.unreadTotal > 0 {
        Text("\(workspace.unreadTotal)")
          .font(.caption.bold())
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Capsule().fill(Color.green))
          .foregroundStyle(.white)
      }

      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    }
  }
}

private struct ConversationRow: View {
  let conversation: ConversationSummary

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(Color.green.opacity(0.18))
        .frame(width: 48, height: 48)
        .overlay(
          Text(String(conversation.title.prefix(1)).uppercased())
            .font(.headline)
            .foregroundStyle(.green)
        )

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(conversation.title)
            .font(.body.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 8)
          if let lastMessageAt = conversation.lastMessageAt {
            Text(lastMessageAt.formatted(date: .omitted, time: .shortened))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        HStack {
          Text(conversation.lastMessagePreview)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer(minLength: 8)

          if conversation.unreadCount > 0 {
            Text("\(conversation.unreadCount)")
              .font(.caption2.bold())
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(Capsule().fill(Color.green))
              .foregroundStyle(.white)
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

private struct UpdateRow: View {
  let item: UpdateItem

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(item.kind == .status ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
        .frame(width: 44, height: 44)
        .overlay(
          Image(systemName: item.kind == .status ? "person.crop.circle" : "megaphone")
            .foregroundStyle(item.kind == .status ? Color.green : Color.blue)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.body.weight(.semibold))
        Text(item.subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 6) {
        Text(item.timestamp.formatted(date: .omitted, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.secondary)

        if item.unread {
          Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

private struct CallRow: View {
  let item: CallItem

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(Color.gray.opacity(0.16))
        .frame(width: 44, height: 44)
        .overlay(
          Image(systemName: iconName)
            .foregroundStyle(iconColor)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text(item.contactName)
          .font(.body.weight(.semibold))
        Text(item.occurredAt.formatted(date: .abbreviated, time: .shortened))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if item.durationSeconds > 0 {
        Text(durationText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var iconName: String {
    switch item.direction {
    case .incoming:
      return "phone.arrow.down.left"
    case .outgoing:
      return "phone.arrow.up.right"
    case .missed:
      return "phone.down.fill"
    }
  }

  private var iconColor: Color {
    switch item.direction {
    case .missed:
      return .red
    case .incoming, .outgoing:
      return .green
    }
  }

  private var durationText: String {
    let minutes = item.durationSeconds / 60
    let seconds = item.durationSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

private struct ThreadRow: View {
  let message: ThreadMessage

  var body: some View {
    HStack {
      if message.direction == .incoming {
        bubble(isIncoming: true)
        Spacer(minLength: 42)
      } else {
        Spacer(minLength: 42)
        bubble(isIncoming: false)
      }
    }
    .padding(.vertical, 2)
  }

  private func bubble(isIncoming: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(message.contentText)
        .font(.body)
        .foregroundColor(isIncoming ? .primary : .white)

      HStack(spacing: 6) {
        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
          .font(.caption2)
          .foregroundColor(isIncoming ? .secondary : .white.opacity(0.9))
        Spacer(minLength: 4)
        Text(deliveryLabel(message.delivery))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(deliveryColor(message.delivery))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(incomingBubbleColor(isIncoming: isIncoming))
        .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
    )
  }

  private func incomingBubbleColor(isIncoming: Bool) -> Color {
    if isIncoming {
      #if os(iOS)
      return Color(uiColor: .secondarySystemBackground)
      #else
      return Color.gray.opacity(0.2)
      #endif
    }
    return Color(red: 0.12, green: 0.60, blue: 0.40)
  }

  private func deliveryLabel(_ status: DeliveryStatus) -> String {
    switch status {
    case .pending:
      return "Enviando"
    case .sent:
      return "Enviada"
    case .delivered:
      return "Entregue"
    case .read:
      return "Lida"
    case .failed:
      return "Falhou"
    }
  }

  private func deliveryColor(_ status: DeliveryStatus) -> Color {
    switch status {
    case .failed:
      return .red
    case .pending:
      return .orange
    case .sent, .delivered:
      return .gray
    case .read:
      return .blue
    }
  }
}

private struct ComposerBar: View {
  @Binding var text: String
  let onSend: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      TextField("Mensagem", text: $text, axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.roundedBorder)

      Button(action: onSend) {
        Image(systemName: "paperplane.fill")
          .font(.title3)
          .frame(width: 36, height: 36)
      }
      .buttonStyle(.borderedProminent)
      .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel("Enviar mensagem")
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background(.thinMaterial)
  }
}

private struct FallbackBanner: View {
  let state: FallbackRenderState
  let openFallbackAction: () -> Void
  let recoverAction: () -> Void

  var body: some View {
    switch state {
    case .native:
      EmptyView()
    case .degraded(let reason):
      banner(
        text: "Modo degradado: \(reason)",
        color: .orange,
        showOpenFallback: true,
        showRecover: false
      )
    case .webViewFallback(let reason, _):
      banner(
        text: "Fallback híbrido ativo: \(reason)",
        color: .red,
        showOpenFallback: true,
        showRecover: true
      )
    case .recovering:
      banner(
        text: "Recuperando render nativo...",
        color: .blue,
        showOpenFallback: false,
        showRecover: false
      )
    }
  }

  private func banner(
    text: String,
    color: Color,
    showOpenFallback: Bool,
    showRecover: Bool
  ) -> some View {
    HStack(spacing: 10) {
      Text(text)
        .font(.caption)
        .foregroundStyle(.white)
      Spacer(minLength: 8)
      if showOpenFallback {
        Button("Abrir fallback web", action: openFallbackAction)
          .font(.caption)
          .buttonStyle(.bordered)
          .tint(.white)
      }
      if showRecover {
        Button("Retomar nativo", action: recoverAction)
          .font(.caption)
          .buttonStyle(.bordered)
          .tint(.white)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background(color)
  }
}

#if os(iOS)
private struct FallbackWebView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    SFSafariViewController(url: url)
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
private struct FallbackWebView: View {
  let url: URL

  var body: some View {
    Text(url.absoluteString)
  }
}
#endif

private extension ThreadMessage {
  var contentText: String {
    switch content {
    case .text(let text):
      return text
    case .media(_, let caption):
      return caption ?? "[Mídia]"
    case .system(let text):
      return text
    }
  }
}
