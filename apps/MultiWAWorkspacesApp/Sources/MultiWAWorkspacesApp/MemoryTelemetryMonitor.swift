import Dispatch
import Foundation
import OSLog
import WorkspaceApplicationServices
import WorkspaceSession
import Darwin.Mach

@MainActor
final class MemoryTelemetryMonitor: ObservableObject {
  private let logger: Logger
  private let runtimeModeProvider: @MainActor () -> SessionRuntimeMode
  private let selectedWorkspaceProvider: @MainActor () -> UUID?
  private let diagnosticsProvider: @MainActor () -> WebSessionDiagnostics?

  private var sampleTask: Task<Void, Never>?
  private var pressureSource: DispatchSourceMemoryPressure?

  init(
    logger: Logger = Logger(subsystem: "com.waspaces.app", category: "memory_telemetry"),
    runtimeModeProvider: @escaping @MainActor () -> SessionRuntimeMode,
    selectedWorkspaceProvider: @escaping @MainActor () -> UUID?,
    diagnosticsProvider: @escaping @MainActor () -> WebSessionDiagnostics?
  ) {
    self.logger = logger
    self.runtimeModeProvider = runtimeModeProvider
    self.selectedWorkspaceProvider = selectedWorkspaceProvider
    self.diagnosticsProvider = diagnosticsProvider
  }

  deinit {
    sampleTask?.cancel()
    pressureSource?.cancel()
  }

  func start() {
    guard sampleTask == nil else {
      return
    }

    configurePressureSourceIfNeeded()
    sampleTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      while !Task.isCancelled {
        emitSample()
        try? await Task.sleep(for: .seconds(15))
      }
    }
  }

  func stop() {
    sampleTask?.cancel()
    sampleTask = nil
    pressureSource?.cancel()
    pressureSource = nil
  }

  private func configurePressureSourceIfNeeded() {
    guard pressureSource == nil else {
      return
    }

    let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .main)
    source.setEventHandler { [weak self] in
      guard let self else {
        return
      }
      let event = source.data
      let state: String
      if event.contains(.critical) {
        state = "critical"
      } else if event.contains(.warning) {
        state = "warning"
      } else {
        state = "normal"
      }

      self.logger.warning(
        "workspace_id=none event=memory_pressure duration_ms=0 result=state=\(state, privacy: .public)_mode=\(self.runtimeModeProvider().rawValue, privacy: .public)"
      )
    }
    source.resume()
    pressureSource = source
  }

  private func emitSample() {
    let runtimeMode = runtimeModeProvider()
    let workspaceID = selectedWorkspaceProvider()?.uuidString ?? "none"
    let diagnostics = diagnosticsProvider()
    let footprintBytes = MemoryTelemetryMonitor.currentMemoryFootprintBytes()

    logger.info(
      "workspace_id=\(workspaceID, privacy: .public) event=memory_sample duration_ms=0 result=mode=\(runtimeMode.rawValue, privacy: .public)_footprint_bytes=\(footprintBytes, privacy: .public)_cached_webviews=\(diagnostics?.cachedWebViewCount ?? -1, privacy: .public)_tracked_webviews=\(diagnostics?.trackedWebViewCount ?? -1, privacy: .public)_tracked_workspaces=\(diagnostics?.trackedWorkspaceCount ?? -1, privacy: .public)"
    )
  }

  nonisolated private static func currentMemoryFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
      }
    }

    guard result == KERN_SUCCESS else {
      return 0
    }

    return info.phys_footprint
  }
}
