import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WorkspaceApplicationServices
import WorkspaceDomain

private enum ActiveWorkspaceSheet: String, Identifiable {
  case create
  case rename

  var id: String { rawValue }
}

private struct WorkspaceIconCropSession: Identifiable {
  let id = UUID()
  let workspace: Workspace
  let sourceImage: NSImage
}

private struct WorkspaceUnreadBadge: View {
  let unread: Int

  var body: some View {
    Text(WorkspaceUnreadBadgeFormatter.text(for: unread))
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .frame(minWidth: 22)
      .background(
        Capsule()
          .fill(Color.red.gradient)
      )
      .overlay(
        Capsule()
          .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
      )
      .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
      .fixedSize()
  }
}

private struct AppKitTextField: NSViewRepresentable {
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: AppKitTextField

    init(parent: AppKitTextField) {
      self.parent = parent
    }

    func controlTextDidChange(_ obj: Notification) {
      guard let textField = obj.object as? NSTextField else {
        return
      }
      parent.text = textField.stringValue
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        parent.onSubmit?()
        return true
      }
      return false
    }
  }

  var placeholder: String
  @Binding var text: String
  var focusRequested: Bool
  var onSubmit: (() -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSTextField {
    let textField = NSTextField(string: text)
    textField.placeholderString = placeholder
    textField.delegate = context.coordinator
    textField.isEditable = true
    textField.isSelectable = true
    textField.isBezeled = true
    textField.bezelStyle = .roundedBezel
    textField.focusRingType = .default
    return textField
  }

  func updateNSView(_ nsView: NSTextField, context: Context) {
    context.coordinator.parent = self

    if nsView.stringValue != text {
      nsView.stringValue = text
    }

    if focusRequested {
      DispatchQueue.main.async {
        guard let window = nsView.window else {
          return
        }
        if window.firstResponder !== nsView.currentEditor() {
          window.makeFirstResponder(nsView)
          nsView.currentEditor()?.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
        }
      }
    }
  }
}

private struct WorkspaceFormSheet: View {
  let title: String
  let fieldTitle: String
  @Binding var value: String
  let confirmTitle: String
  let onCancel: () -> Void
  let onConfirm: () -> Void

  @State private var shouldRequestFocus = true

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title)
        .font(.title3.bold())

      AppKitTextField(
        placeholder: fieldTitle,
        text: $value,
        focusRequested: shouldRequestFocus,
        onSubmit: onConfirm
      )
      .frame(height: 26)

      HStack {
        Spacer()
        Button("Cancelar") {
          onCancel()
        }
        Button(confirmTitle) {
          onConfirm()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 380)
    .onAppear {
      shouldRequestFocus = true
    }
  }
}

struct WorkspaceShellView: View {
  @ObservedObject var manager: WorkspaceManager
  let iconAssetStore: WorkspaceIconAssetStore
  @ObservedObject var uiSettingsStore: WorkspaceUISettingsStore
  let activeRuntimeMode: SessionRuntimeMode
  let processPendingCleanupNow: @MainActor () async -> Void
  let reloadActiveWorkspaceNow: @MainActor () async throws -> Void

  @State private var selectedWorkspaceID: UUID?
  @State private var createWorkspaceName = ""
  @State private var renameWorkspaceName = ""
  @State private var workspaceToRename: Workspace?
  @State private var activeSheet: ActiveWorkspaceSheet?
  @State private var activeCropSession: WorkspaceIconCropSession?
  @State private var pendingDeletionWorkspaceIDs: [UUID] = []
  @State private var isShowingDeleteDialog = false
  @State private var editingSelection: Set<UUID> = []
  @State private var flyoutState = WorkspaceFlyoutState()
  @State private var alertMessage: String?
  @State private var isMenuHoverTargetHovered = false
  @State private var isFlyoutHovered = false
  @State private var isFlyoutVisible = false
  @State private var closeFlyoutTask: Task<Void, Never>?
  @State private var isProcessingPendingCleanup = false

  private let railWidth: CGFloat = 82
  private let flyoutWidth: CGFloat = 372
  private let flyoutCloseDelay: Duration = .milliseconds(190)
  private let railAvatarSize: CGFloat = 40
  private let rowAvatarSize: CGFloat = 32

  init(
    manager: WorkspaceManager,
    iconAssetStore: WorkspaceIconAssetStore,
    uiSettingsStore: WorkspaceUISettingsStore,
    activeRuntimeMode: SessionRuntimeMode,
    processPendingCleanupNow: @escaping @MainActor () async -> Void = {},
    reloadActiveWorkspaceNow: @escaping @MainActor () async throws -> Void = {}
  ) {
    self.manager = manager
    self.iconAssetStore = iconAssetStore
    self.uiSettingsStore = uiSettingsStore
    self.activeRuntimeMode = activeRuntimeMode
    self.processPendingCleanupNow = processPendingCleanupNow
    self.reloadActiveWorkspaceNow = reloadActiveWorkspaceNow
  }

  var body: some View {
    ZStack(alignment: .leading) {
      HStack(spacing: 0) {
        railPane
        Divider()
        detailPane
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if isFlyoutVisible {
        flyoutPane
          .frame(width: flyoutWidth)
          .frame(maxHeight: .infinity)
          .offset(x: railWidth)
          .transition(.opacity.combined(with: .move(edge: .leading)))
          .zIndex(10)
      }
    }
    .animation(.easeInOut(duration: 0.14), value: isFlyoutVisible)
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .create:
        WorkspaceFormSheet(
          title: "Novo Workspace",
          fieldTitle: "Nome",
          value: $createWorkspaceName,
          confirmTitle: "Criar",
          onCancel: closeSheet,
          onConfirm: {
            Task {
              await createWorkspace()
            }
          }
        )
      case .rename:
        WorkspaceFormSheet(
          title: "Renomear Workspace",
          fieldTitle: "Nome",
          value: $renameWorkspaceName,
          confirmTitle: "Salvar",
          onCancel: closeSheet,
          onConfirm: {
            Task {
              await renameWorkspace()
            }
          }
        )
      }
    }
    .sheet(item: $activeCropSession) { session in
      WorkspaceAvatarCropSheet(
        workspaceName: session.workspace.name,
        sourceImage: session.sourceImage,
        onCancel: {
          activeCropSession = nil
        },
        onConfirm: { state in
          Task {
            await saveCroppedIcon(session: session, state: state)
          }
        }
      )
    }
    .confirmationDialog(
      deleteDialogTitle,
      isPresented: $isShowingDeleteDialog,
      titleVisibility: .visible
    ) {
      Button("Remover", role: .destructive) {
        Task {
          await removeSelectedWorkspaces()
        }
      }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text(deleteDialogMessage)
    }
    .alert("Erro", isPresented: Binding(
      get: { alertMessage != nil },
      set: { if !$0 { alertMessage = nil } }
    )) {
      Button("Fechar", role: .cancel) {}
    } message: {
      Text(alertMessage ?? "")
    }
    .onReceive(manager.$selectedWorkspaceID) { selected in
      if selectedWorkspaceID != selected {
        selectedWorkspaceID = selected
      }
    }
    .onReceive(manager.$workspaces) { workspaces in
      syncDefaultWorkspaceFallback(with: workspaces)
    }
    .task {
      do {
        let list = try await manager.list()
        if selectedWorkspaceID == nil {
          selectedWorkspaceID = WorkspaceSelectionDefaults.preferredWorkspaceID(
            defaultID: uiSettingsStore.settings.defaultWorkspaceID,
            workspaces: list
          )
        }
        if let selectedWorkspaceID {
          try await manager.select(id: selectedWorkspaceID)
        }
      } catch {
        alertMessage = error.localizedDescription
      }
    }
    .onDisappear {
      closeFlyoutTask?.cancel()
    }
  }

  private var railPane: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 10) {
          ForEach(manager.workspaces) { workspace in
            railWorkspaceButton(for: workspace)
          }

          if manager.workspaces.isEmpty {
            Image(systemName: "rectangle.stack.badge.person.crop")
              .font(.title3)
              .foregroundStyle(.secondary)
              .frame(width: 52, height: 52)
              .background(.thinMaterial, in: Circle())
              .padding(.top, 4)
          }
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .frame(maxHeight: .infinity, alignment: .top)

      Divider()

      railFooterActions
        .padding(.vertical, 10)
    }
    .frame(width: railWidth)
    .frame(maxHeight: .infinity)
    .background(
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        LinearGradient(
          colors: [.white.opacity(0.10), .clear, .black.opacity(0.08)],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    )
    .overlay(
      Rectangle()
        .stroke(.white.opacity(0.08), lineWidth: 1)
    )
  }

  private var flyoutPane: some View {
    VStack(spacing: 0) {
      flyoutHeader

      Divider()

      if flyoutState.panel == .config {
        settingsPanel
      } else if flyoutState.canReorder {
        editingWorkspaceList
      } else {
        browsingWorkspaceList
      }
    }
    .background(
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        LinearGradient(
          colors: [.white.opacity(0.14), .white.opacity(0.02), .black.opacity(0.10)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    )
    .overlay(
      RoundedRectangle(cornerRadius: 0)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.24), radius: 18, x: 8, y: 0)
    .onHover { hovering in
      isFlyoutHovered = hovering
      if hovering {
        openFlyout()
      } else {
        scheduleFlyoutCloseIfNeeded()
      }
    }
  }

  private var flyoutHeader: some View {
    VStack(spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Workspaces")
            .font(.system(size: 22, weight: .bold, design: .rounded))

          if flyoutState.canReorder {
            Text("\(editingSelection.count) selecionados")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else if flyoutState.panel == .config {
            Text("Configurações")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text("Gerencie sessões isoladas")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        HStack(spacing: 8) {
          if flyoutState.canReorder {
            Button {
              toggleEditMode()
            } label: {
              Label("Concluir", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button {
              toggleEditMode()
            } label: {
              Label("Editar", systemImage: "square.and.pencil")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
          }

          if flyoutState.panel == .config {
            Button {
              toggleConfigPanel()
            } label: {
              Label("Config", systemImage: "gearshape")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button {
              toggleConfigPanel()
            } label: {
              Label("Config", systemImage: "gearshape")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
      LinearGradient(
        colors: [.white.opacity(0.16), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var browsingWorkspaceList: some View {
    List(manager.workspaces) { workspace in
      Button {
        Task {
          await selectWorkspace(id: workspace.id, collapseFlyout: true)
        }
      } label: {
        workspaceListRow(for: workspace, showSelectionControl: false)
      }
      .buttonStyle(.plain)
      .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .contextMenu {
        Button("Renomear") {
          openRenameSheet(for: workspace)
        }

        Button(workspace.iconAssetPath == nil ? "Definir foto do ícone..." : "Recortar/alterar foto...") {
          Task {
            await requestWorkspaceIconCrop(for: workspace)
          }
        }

        Button("Remover foto do ícone") {
          Task {
            await clearWorkspaceIcon(for: workspace)
          }
        }
        .disabled(workspace.iconAssetPath == nil)

        Button("Remover", role: .destructive) {
          requestDeletion(for: [workspace.id])
        }
      }
    }
    .scrollContentBackground(.hidden)
    .listStyle(.plain)
  }

  private var editingWorkspaceList: some View {
    List {
      ForEach(manager.workspaces) { workspace in
        workspaceListRow(for: workspace, showSelectionControl: true)
          .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }
      .onMove(perform: moveWorkspaces)
    }
    .scrollContentBackground(.hidden)
    .listStyle(.plain)
  }

  private var settingsPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        GroupBox("Preferências") {
          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Modo de runtime")
                .font(.caption)
                .foregroundStyle(.secondary)

              Picker(
                "Modo de runtime",
                selection: Binding(
                  get: { uiSettingsStore.settings.sessionRuntimeMode },
                  set: { uiSettingsStore.setSessionRuntimeMode($0) }
                )
              ) {
                ForEach(SessionRuntimeMode.allCases) { mode in
                  Text(mode.title).tag(mode)
                }
              }

              if activeRuntimeMode != uiSettingsStore.settings.sessionRuntimeMode {
                Text("Ativo agora: \(activeRuntimeMode.title)")
                  .font(.caption2)
                  .foregroundStyle(.orange)
              } else {
                Text(activeRuntimeMode.description)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }

            Toggle(
              "Notificações do app",
              isOn: Binding(
                get: { uiSettingsStore.settings.notificationsEnabled },
                set: { uiSettingsStore.setNotificationsEnabled($0) }
              )
            )

            Toggle(
              "Badges de não lidas",
              isOn: Binding(
                get: { uiSettingsStore.settings.showBadges },
                set: { uiSettingsStore.setShowBadges($0) }
              )
            )

            VStack(alignment: .leading, spacing: 6) {
              Text("Workspace padrão na abertura")
                .font(.caption)
                .foregroundStyle(.secondary)

              Picker(
                "Workspace padrão",
                selection: Binding(
                  get: { uiSettingsStore.settings.defaultWorkspaceID },
                  set: { uiSettingsStore.setDefaultWorkspaceID($0) }
                )
              ) {
                Text("Primeiro disponível").tag(UUID?.none)
                ForEach(manager.workspaces) { workspace in
                  Text(workspace.name).tag(Optional(workspace.id))
                }
              }
            }
          }
          .padding(.top, 6)
        }

        GroupBox("Manutenção") {
          VStack(alignment: .leading, spacing: 10) {
            Button {
              Task {
                isProcessingPendingCleanup = true
                await processPendingCleanupNow()
                isProcessingPendingCleanup = false
              }
            } label: {
              HStack {
                Text("Processar limpezas pendentes agora")
                if isProcessingPendingCleanup {
                  ProgressView()
                    .controlSize(.small)
                }
              }
            }
            .disabled(isProcessingPendingCleanup)

            Button {
              Task {
                do {
                  try await reloadActiveWorkspaceNow()
                } catch {
                  alertMessage = error.localizedDescription
                }
              }
            } label: {
              Text("Recarregar workspace ativo")
            }
          }
          .padding(.top, 6)
        }
      }
      .padding(12)
    }
  }

  @ViewBuilder
  private var detailPane: some View {
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
      VStack(spacing: 16) {
        ContentUnavailableView(
          "Selecione um workspace",
          systemImage: "rectangle.stack.badge.person.crop",
          description: Text("Crie ou selecione um workspace para abrir o WhatsApp Web isolado.")
        )

        HStack(spacing: 10) {
          Button {
            Task {
              await createWorkspaceQuickly()
            }
          } label: {
            Label("Criar workspace rápido", systemImage: "bolt.fill")
          }
          .buttonStyle(.borderedProminent)

          Button {
            openCreateSheet()
          } label: {
            Label("Criar com nome", systemImage: "plus")
          }
          .buttonStyle(.bordered)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var railFooterActions: some View {
    HStack(spacing: 12) {
      Button {
        Task {
          await createWorkspaceQuickly()
        }
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.title2)
      }
      .buttonStyle(.plain)
      .help("Adicionar workspace")

      Button {
        openFlyout()
      } label: {
        Image(systemName: isFlyoutVisible ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.circle.fill")
          .font(.title2)
      }
      .buttonStyle(.plain)
      .help("Menu de workspaces")
      .onHover { hovering in
        isMenuHoverTargetHovered = hovering
        if hovering {
          openFlyout()
        } else {
          scheduleFlyoutCloseIfNeeded()
        }
      }
    }
    .frame(maxWidth: .infinity)
    .foregroundStyle(.primary)
  }

  private func railWorkspaceButton(for workspace: Workspace) -> some View {
    let unread = manager.unreadByWorkspace[workspace.id] ?? 0
    let isActive = selectedWorkspaceID == workspace.id

    return Button {
      Task {
        await selectWorkspace(id: workspace.id, collapseFlyout: false)
      }
    } label: {
      ZStack(alignment: .topTrailing) {
        workspaceAvatar(for: workspace, size: railAvatarSize)
          .frame(width: railAvatarSize, height: railAvatarSize)
          .overlay {
            Circle()
              .stroke(isActive ? Color.accentColor : Color.white.opacity(0.22), lineWidth: isActive ? 2 : 1)
          }
          .shadow(color: .black.opacity(isActive ? 0.35 : 0.2), radius: isActive ? 5 : 3, x: 0, y: 2)

        if shouldDisplayUnread(unread) {
          WorkspaceUnreadBadge(unread: unread)
            .padding(.top, -2)
            .padding(.trailing, -4)
        }
      }
      .frame(width: railAvatarSize + 20, height: railAvatarSize + 20)
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .help(workspace.name)
  }

  private func workspaceListRow(for workspace: Workspace, showSelectionControl: Bool) -> some View {
    let unread = manager.unreadByWorkspace[workspace.id] ?? 0
    let isSelectedForDelete = editingSelection.contains(workspace.id)
    let isActive = selectedWorkspaceID == workspace.id

    return HStack(spacing: 10) {
      if showSelectionControl {
        Button {
          toggleEditingSelection(for: workspace.id)
        } label: {
          Image(systemName: isSelectedForDelete ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(isSelectedForDelete ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
      }

      workspaceAvatar(for: workspace, size: rowAvatarSize)

      VStack(alignment: .leading, spacing: 2) {
        Text(workspace.name)
          .font(.headline)
          .lineLimit(1)
        Text(stateLabel(for: workspace.state))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      if shouldDisplayUnread(unread) {
        WorkspaceUnreadBadge(unread: unread)
      }

      if showSelectionControl {
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(.tertiary)
      }
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(isActive && !showSelectionControl ? Color.accentColor.opacity(0.17) : Color.white.opacity(0.07))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(isActive && !showSelectionControl ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      if showSelectionControl {
        toggleEditingSelection(for: workspace.id)
      }
    }
  }

  @ViewBuilder
  private func workspaceAvatar(for workspace: Workspace, size: CGFloat) -> some View {
    if let image = iconAssetStore.image(for: workspace.iconAssetPath) {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
    } else {
      Circle()
        .fill(color(for: workspace.colorTag))
        .frame(width: size, height: size)
        .overlay(
          Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: max(10, size * 0.36), weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
        )
    }
  }

  private var selectedWorkspace: Workspace? {
    guard let selectedWorkspaceID else {
      return nil
    }
    return manager.workspaces.first(where: { $0.id == selectedWorkspaceID })
  }

  private var deleteDialogTitle: String {
    if pendingDeletionWorkspaceIDs.count > 1 {
      return "Remover \(pendingDeletionWorkspaceIDs.count) workspaces"
    }
    return "Remover workspace"
  }

  private var deleteDialogMessage: String {
    if pendingDeletionWorkspaceIDs.count > 1 {
      return "As sessões dos workspaces selecionados serão encerradas e os datastores locais serão removidos."
    }
    return "A sessão deste workspace será encerrada e o datastore local será removido."
  }

  private func openCreateSheet() {
    createWorkspaceName = ""
    activeSheet = .create
  }

  private func openRenameSheet(for workspace: Workspace) {
    workspaceToRename = workspace
    renameWorkspaceName = workspace.name
    activeSheet = .rename
  }

  private func closeSheet() {
    activeSheet = nil
  }

  private func syncDefaultWorkspaceFallback(with workspaces: [Workspace]) {
    let ids = workspaces.map(\.id)
    let sanitizedDefault = WorkspaceSelectionDefaults.sanitizedDefaultID(
      defaultID: uiSettingsStore.settings.defaultWorkspaceID,
      availableIDs: ids
    )

    if sanitizedDefault != uiSettingsStore.settings.defaultWorkspaceID {
      uiSettingsStore.setDefaultWorkspaceID(sanitizedDefault)
    }
  }

  private func generateWorkspaceName() -> String {
    let existingNames = Set(manager.workspaces.map { $0.name.lowercased() })
    var index = max(1, manager.workspaces.count + 1)
    while true {
      let candidate = "Workspace \(index)"
      if !existingNames.contains(candidate.lowercased()) {
        return candidate
      }
      index += 1
    }
  }

  private func createWorkspaceQuickly() async {
    do {
      let workspace = try await manager.create(name: generateWorkspaceName())
      await selectWorkspace(id: workspace.id, collapseFlyout: false)
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func createWorkspace() async {
    do {
      let workspace = try await manager.create(name: createWorkspaceName)
      closeSheet()
      await selectWorkspace(id: workspace.id, collapseFlyout: false)
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
      self.workspaceToRename = nil
      closeSheet()
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func requestDeletion(for workspaceIDs: [UUID]) {
    let uniqueIDs = Array(Set(workspaceIDs)).sorted { $0.uuidString < $1.uuidString }
    guard !uniqueIDs.isEmpty else {
      return
    }
    pendingDeletionWorkspaceIDs = uniqueIDs
    isShowingDeleteDialog = true
  }

  private func removeSelectedWorkspaces() async {
    let targetIDs = pendingDeletionWorkspaceIDs
    guard !targetIDs.isEmpty else {
      return
    }

    do {
      for workspaceID in targetIDs {
        try await manager.remove(id: workspaceID)
      }

      pendingDeletionWorkspaceIDs = []
      editingSelection.subtract(targetIDs)

      if let selectedWorkspaceID, targetIDs.contains(selectedWorkspaceID) {
        self.selectedWorkspaceID = WorkspaceSelectionDefaults.preferredWorkspaceID(
          defaultID: uiSettingsStore.settings.defaultWorkspaceID,
          workspaces: manager.workspaces
        )
      } else if self.selectedWorkspaceID == nil {
        self.selectedWorkspaceID = WorkspaceSelectionDefaults.preferredWorkspaceID(
          defaultID: uiSettingsStore.settings.defaultWorkspaceID,
          workspaces: manager.workspaces
        )
      }

      if let selectedWorkspaceID {
        await selectWorkspace(id: selectedWorkspaceID, collapseFlyout: false)
      }
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func moveWorkspaces(from source: IndexSet, to destination: Int) {
    Task {
      do {
        try await manager.reorder(fromOffsets: source, toOffset: destination)
      } catch {
        alertMessage = error.localizedDescription
      }
    }
  }

  private func toggleEditingSelection(for workspaceID: UUID) {
    if editingSelection.contains(workspaceID) {
      editingSelection.remove(workspaceID)
    } else {
      editingSelection.insert(workspaceID)
    }
  }

  private func toggleEditMode() {
    flyoutState.toggleEdit()
    if !flyoutState.canReorder {
      editingSelection.removeAll()
      scheduleFlyoutCloseIfNeeded()
    } else {
      openFlyout()
    }
  }

  private func toggleConfigPanel() {
    flyoutState.toggleConfig()
    if flyoutState.panel == .config {
      editingSelection.removeAll()
      openFlyout()
    } else {
      scheduleFlyoutCloseIfNeeded()
    }
  }

  private func requestWorkspaceIconCrop(for workspace: Workspace) async {
    let panel = NSOpenPanel()
    panel.title = "Selecionar foto do workspace"
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.image]

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      return
    }

    guard let sourceImage = NSImage(contentsOf: selectedURL) else {
      alertMessage = "Não foi possível abrir a imagem selecionada."
      return
    }

    activeCropSession = WorkspaceIconCropSession(workspace: workspace, sourceImage: sourceImage)
  }

  private func saveCroppedIcon(session: WorkspaceIconCropSession, state: WorkspaceAvatarCropState) async {
    do {
      let pngData = try WorkspaceAvatarCropRenderer.renderPNG(from: session.sourceImage, state: state)
      let relativePath = try iconAssetStore.saveNormalizedPNG(pngData, workspaceID: session.workspace.id)

      do {
        try await manager.setIconAssetPath(id: session.workspace.id, iconAssetPath: relativePath)
      } catch {
        try? iconAssetStore.removeIcon(relativePath: relativePath)
        throw error
      }

      activeCropSession = nil
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func clearWorkspaceIcon(for workspace: Workspace) async {
    guard let iconPath = workspace.iconAssetPath else {
      return
    }

    do {
      try await manager.clearIconAssetPath(id: workspace.id)
      try? iconAssetStore.removeIcon(relativePath: iconPath)
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func selectWorkspace(id: UUID, collapseFlyout: Bool) async {
    do {
      selectedWorkspaceID = id
      try await manager.select(id: id)
      if collapseFlyout && !flyoutState.canReorder && flyoutState.panel == .workspaces {
        closeFlyoutImmediately()
      }
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  private func openFlyout() {
    closeFlyoutTask?.cancel()
    closeFlyoutTask = nil
    isFlyoutVisible = true
  }

  private func closeFlyoutImmediately() {
    closeFlyoutTask?.cancel()
    closeFlyoutTask = nil
    isFlyoutVisible = false
    if flyoutState.panel == .config {
      flyoutState.panel = .workspaces
    }
  }

  private func scheduleFlyoutCloseIfNeeded() {
    guard !flyoutState.canReorder else {
      return
    }

    closeFlyoutTask?.cancel()
    closeFlyoutTask = Task { @MainActor in
      try? await Task.sleep(for: flyoutCloseDelay)
      guard !Task.isCancelled else {
        return
      }
      guard !isMenuHoverTargetHovered && !isFlyoutHovered else {
        return
      }
      closeFlyoutImmediately()
    }
  }

  private func shouldDisplayUnread(_ unread: Int) -> Bool {
    uiSettingsStore.settings.showBadges && unread > 0
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
