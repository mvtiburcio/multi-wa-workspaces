#if os(iOS)
import SwiftUI
import WorkspaceDomain

struct IOSWebKitRootView: View {
  @ObservedObject var model: IOSWebKitAppModel
  @State private var activeTab: WebKitTab = .chats
  @State private var isWorkspaceSheetPresented = false

  enum WebKitTab: Hashable {
    case chats
    case updates
    case calls
    case settings
  }

  var body: some View {
    TabView(selection: $activeTab) {
      chatsTab
        .tabItem { Label("Chats", systemImage: "message") }
        .tag(WebKitTab.chats)

      placeholderTab(
        title: "Atualizações",
        icon: "circle.dashed.inset.filled",
        description: "Esta aba será consolidada após o parser nativo por sessão WebKit."
      )
      .tabItem { Label("Atualizações", systemImage: "circle.dashed.inset.filled") }
      .tag(WebKitTab.updates)

      placeholderTab(
        title: "Chamadas",
        icon: "phone",
        description: "Esta aba ficará em leitura quando o domínio de chamadas estiver estabilizado."
      )
      .tabItem { Label("Chamadas", systemImage: "phone") }
      .tag(WebKitTab.calls)

      settingsTab
        .tabItem { Label("Ajustes", systemImage: "gearshape") }
        .tag(WebKitTab.settings)
    }
    .task {
      await model.bootstrap()
    }
    .sheet(isPresented: $isWorkspaceSheetPresented) {
      IOSWorkspaceSwitcherSheet(model: model)
        .presentationDetents([.medium, .large])
    }
  }

  private var chatsTab: some View {
    NavigationStack {
      Group {
        if model.isBootstrapping {
          ProgressView("Carregando sessões WebKit...")
        } else if let error = model.bootstrapErrorMessage {
          ContentUnavailableView("Falha ao carregar", systemImage: "exclamationmark.triangle", description: Text(error))
            .padding()
        } else if let webView = model.manager.selectedWebView {
          IOSWorkspaceWebView(webView: webView)
            .overlay(alignment: .bottom) {
              Text("Escaneie o QR exibido no WhatsApp Web deste workspace")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        } else {
          ContentUnavailableView(
            "Nenhum workspace ativo",
            systemImage: "link.badge.plus",
            description: Text("Crie ou selecione um workspace para abrir uma sessão isolada.")
          )
          .padding()
        }
      }
      .navigationTitle("Chats")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            isWorkspaceSheetPresented = true
          } label: {
            HStack(spacing: 8) {
              Circle()
                .fill(color(for: model.selectedWorkspace?.state ?? .cold))
                .frame(width: 10, height: 10)
              Text(model.selectedWorkspace?.name ?? "Workspace")
                .lineLimit(1)
            }
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isWorkspaceSheetPresented = true
          } label: {
            Image(systemName: "plus.circle")
          }
        }
      }
    }
  }

  private var settingsTab: some View {
    NavigationStack {
      List {
        Section("Workspace ativo") {
          if let workspace = model.selectedWorkspace {
            HStack {
              Circle()
                .fill(color(for: workspace.state))
                .frame(width: 10, height: 10)
              VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name)
                Text(model.stateLabel(workspace.state))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } else {
            Text("Nenhum workspace selecionado")
          }
        }

        Section("Sessão") {
          Button("Trocar workspace") {
            isWorkspaceSheetPresented = true
          }
          Button("Recarregar sessão ativa") {
            Task {
              await model.reloadSelectedWorkspace()
            }
          }
        }

        Section("Runtime") {
          Text("Motor de sessão: WebKit (isolamento por data store)")
          Text("Fonte: web.whatsapp.com")
        }
      }
      .navigationTitle("Ajustes")
    }
  }

  private func placeholderTab(title: String, icon: String, description: String) -> some View {
    NavigationStack {
      ContentUnavailableView(title, systemImage: icon, description: Text(description))
        .padding()
        .navigationTitle(title)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              isWorkspaceSheetPresented = true
            } label: {
              HStack(spacing: 8) {
                Circle()
                  .fill(color(for: model.selectedWorkspace?.state ?? .cold))
                  .frame(width: 10, height: 10)
                Text(model.selectedWorkspace?.name ?? "Workspace")
                  .lineLimit(1)
              }
            }
          }
        }
    }
  }

  private func color(for state: WorkspaceState) -> Color {
    switch state {
    case .connected:
      return .green
    case .loading, .qrRequired:
      return .orange
    case .disconnected, .failed:
      return .red
    case .cold:
      return .gray
    }
  }
}

private struct IOSWorkspaceSwitcherSheet: View {
  @ObservedObject var model: IOSWebKitAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Workspaces") {
          ForEach(model.manager.workspaces) { workspace in
            Button {
              Task {
                await model.selectWorkspace(workspace.id)
                dismiss()
              }
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(workspace.name)
                  Text(model.stateLabel(workspace.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if model.manager.selectedWorkspaceID == workspace.id {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                }
              }
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                Task {
                  await model.removeWorkspace(workspace.id)
                }
              } label: {
                Label("Remover", systemImage: "trash")
              }
            }
          }
        }

        Section("Novo workspace") {
          TextField("Nome do workspace", text: $model.newWorkspaceName)
            .textInputAutocapitalization(.words)
          Button("Criar e abrir") {
            Task {
              await model.createWorkspace()
            }
          }
          .disabled(model.newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .navigationTitle("Workspaces")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Fechar") { dismiss() }
        }
      }
    }
  }
}
#endif
