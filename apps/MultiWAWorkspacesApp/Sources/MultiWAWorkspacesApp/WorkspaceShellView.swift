import SwiftUI
import WorkspaceApplicationServices
import WorkspaceDomain

struct WorkspaceShellView: View {
  @ObservedObject var manager: WorkspaceManager

  @State private var selectedWorkspaceID: UUID?
  @State private var createWorkspaceName = ""
  @State private var renameWorkspaceName = ""
  @State private var workspaceToRename: Workspace?
  @State private var workspaceToDelete: Workspace?
  @State private var isShowingCreateSheet = false
  @State private var isShowingRenameSheet = false
  @State private var isShowingDeleteDialog = false
  @State private var alertMessage: String?

  var body: some View {
    NavigationSplitView {
      List(manager.workspaces, selection: $selectedWorkspaceID) { workspace in
        HStack(spacing: 10) {
          Circle()
            .fill(color(for: workspace.colorTag))
            .frame(width: 10, height: 10)
          VStack(alignment: .leading, spacing: 2) {
            Text(workspace.name)
              .font(.headline)
            Text(stateLabel(for: workspace.state))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text(workspace.state.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(stateColor(for: workspace.state).opacity(0.18))
            )
            .foregroundStyle(stateColor(for: workspace.state))
        }
        .tag(workspace.id)
        .contextMenu {
          Button("Renomear") {
            workspaceToRename = workspace
            renameWorkspaceName = workspace.name
            isShowingRenameSheet = true
          }
          Button("Remover", role: .destructive) {
            workspaceToDelete = workspace
            isShowingDeleteDialog = true
          }
        }
      }
      .navigationTitle("Workspaces")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            createWorkspaceName = ""
            isShowingCreateSheet = true
          } label: {
            Label("Novo Workspace", systemImage: "plus")
          }
        }

        ToolbarItem(placement: .automatic) {
          Button {
            guard let selectedWorkspace = selectedWorkspace else {
              return
            }
            workspaceToRename = selectedWorkspace
            renameWorkspaceName = selectedWorkspace.name
            isShowingRenameSheet = true
          } label: {
            Label("Renomear", systemImage: "pencil")
          }
          .disabled(selectedWorkspace == nil)
        }

        ToolbarItem(placement: .automatic) {
          Button(role: .destructive) {
            guard let selectedWorkspace = selectedWorkspace else {
              return
            }
            workspaceToDelete = selectedWorkspace
            isShowingDeleteDialog = true
          } label: {
            Label("Remover", systemImage: "trash")
          }
          .disabled(selectedWorkspace == nil)
        }
      }
    } detail: {
      if let webView = manager.selectedWebView {
        ZStack(alignment: .topTrailing) {
          WorkspaceWebView(webView: webView)
            .ignoresSafeArea()

          if let selectedWorkspace {
            Text(stateLabel(for: selectedWorkspace.state))
              .font(.caption)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(
                Capsule()
                  .fill(.ultraThinMaterial)
              )
              .overlay(
                Capsule()
                  .stroke(stateColor(for: selectedWorkspace.state), lineWidth: 1)
              )
              .padding()
          }
        }
      } else {
        ContentUnavailableView(
          "Selecione um workspace",
          systemImage: "rectangle.stack.badge.person.crop",
          description: Text("Crie ou selecione um workspace para abrir o WhatsApp Web isolado.")
        )
      }
    }
    .sheet(isPresented: $isShowingCreateSheet) {
      workspaceForm(
        title: "Novo Workspace",
        fieldTitle: "Nome",
        value: $createWorkspaceName,
        confirmTitle: "Criar"
      ) {
        Task {
          await createWorkspace()
        }
      }
    }
    .sheet(isPresented: $isShowingRenameSheet) {
      workspaceForm(
        title: "Renomear Workspace",
        fieldTitle: "Nome",
        value: $renameWorkspaceName,
        confirmTitle: "Salvar"
      ) {
        Task {
          await renameWorkspace()
        }
      }
    }
    .confirmationDialog(
      "Remover Workspace",
      isPresented: $isShowingDeleteDialog,
      titleVisibility: .visible
    ) {
      Button("Remover", role: .destructive) {
        Task {
          await removeWorkspace()
        }
      }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("A sessão deste workspace será encerrada e o datastore local será removido.")
    }
    .alert("Erro", isPresented: Binding(
      get: { alertMessage != nil },
      set: { if !$0 { alertMessage = nil } }
    )) {
      Button("Fechar", role: .cancel) {}
    } message: {
      Text(alertMessage ?? "")
    }
    .onChange(of: selectedWorkspaceID) { _, newValue in
      guard let newValue else {
        return
      }
      Task {
        do {
          try await manager.select(id: newValue)
        } catch {
          alertMessage = error.localizedDescription
        }
      }
    }
    .onReceive(manager.$selectedWorkspaceID) { selected in
      if selectedWorkspaceID != selected {
        selectedWorkspaceID = selected
      }
    }
    .task {
      do {
        let list = try await manager.list()
        if selectedWorkspaceID == nil {
          selectedWorkspaceID = list.first?.id
        }
        if let selectedWorkspaceID {
          try await manager.select(id: selectedWorkspaceID)
        }
      } catch {
        alertMessage = error.localizedDescription
      }
    }
  }

  private var selectedWorkspace: Workspace? {
    guard let selectedWorkspaceID else {
      return nil
    }
    return manager.workspaces.first(where: { $0.id == selectedWorkspaceID })
  }

  private func workspaceForm(
    title: String,
    fieldTitle: String,
    value: Binding<String>,
    confirmTitle: String,
    onConfirm: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title)
        .font(.title3.bold())

      TextField(fieldTitle, text: value)
        .textFieldStyle(.roundedBorder)

      HStack {
        Spacer()
        Button("Cancelar") {
          isShowingCreateSheet = false
          isShowingRenameSheet = false
        }
        Button(confirmTitle) {
          onConfirm()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 360)
  }

  private func createWorkspace() async {
    do {
      let workspace = try await manager.create(name: createWorkspaceName)
      isShowingCreateSheet = false
      selectedWorkspaceID = workspace.id
      try await manager.select(id: workspace.id)
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func renameWorkspace() async {
    guard let workspaceToRename else {
      return
    }

    do {
      try await manager.rename(id: workspaceToRename.id, newName: renameWorkspaceName)
      isShowingRenameSheet = false
      self.workspaceToRename = nil
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func removeWorkspace() async {
    guard let workspaceToDelete else {
      return
    }

    do {
      try await manager.remove(id: workspaceToDelete.id)
      self.workspaceToDelete = nil
      selectedWorkspaceID = manager.workspaces.first?.id
      if let selectedWorkspaceID {
        try await manager.select(id: selectedWorkspaceID)
      }
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func color(for colorTag: String) -> Color {
    switch colorTag {
    case "blue": .blue
    case "green": .green
    case "orange": .orange
    case "red": .red
    case "teal": .teal
    case "indigo": .indigo
    case "pink": .pink
    case "amber": .yellow
    default: .gray
    }
  }

  private func stateColor(for state: WorkspaceState) -> Color {
    switch state {
    case .cold: .gray
    case .loading: .orange
    case .qrRequired: .purple
    case .connected: .green
    case .disconnected: .orange
    case .failed: .red
    }
  }

  private func stateLabel(for state: WorkspaceState) -> String {
    switch state {
    case .cold: "Aguardando abertura"
    case .loading: "Carregando sessão"
    case .qrRequired: "Aguardando leitura de QR"
    case .connected: "Conectado"
    case .disconnected: "Desconectado"
    case .failed: "Falha na sessão"
    }
  }
}
