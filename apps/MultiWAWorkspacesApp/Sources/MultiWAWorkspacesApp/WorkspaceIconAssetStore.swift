import Foundation

@MainActor
final class WorkspaceIconAssetStore {
  private let fileManager: FileManager
  private let baseDirectoryURL: URL
  private let iconsDirectoryURL: URL

  init(fileManager: FileManager = .default) throws {
    self.fileManager = fileManager

    let appSupportURL = try Self.applicationSupportDirectory(fileManager: fileManager)
    let baseDirectoryURL = appSupportURL.appendingPathComponent("com.multiwa.workspaces", isDirectory: true)
    let iconsDirectoryURL = baseDirectoryURL.appendingPathComponent("workspace-icons", isDirectory: true)

    self.baseDirectoryURL = baseDirectoryURL
    self.iconsDirectoryURL = iconsDirectoryURL

    try fileManager.createDirectory(at: iconsDirectoryURL, withIntermediateDirectories: true)
  }

  func importIcon(from sourceURL: URL, workspaceID: UUID) throws -> String {
    try fileManager.createDirectory(at: iconsDirectoryURL, withIntermediateDirectories: true)

    let pathExtension = normalizedPathExtension(from: sourceURL)
    let fileName = "\(workspaceID.uuidString).\(pathExtension)"
    let destinationURL = iconsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

    try removeExistingIcons(for: workspaceID, preserving: destinationURL.lastPathComponent)

    if fileManager.fileExists(atPath: destinationURL.path) {
      try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.copyItem(at: sourceURL, to: destinationURL)

    return "workspace-icons/\(fileName)"
  }

  func saveNormalizedPNG(_ pngData: Data, workspaceID: UUID) throws -> String {
    try fileManager.createDirectory(at: iconsDirectoryURL, withIntermediateDirectories: true)

    let fileName = "\(workspaceID.uuidString).png"
    let destinationURL = iconsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    try removeExistingIcons(for: workspaceID, preserving: fileName)

    try pngData.write(to: destinationURL, options: [.atomic])
    return "workspace-icons/\(fileName)"
  }

  func removeIcon(relativePath: String) throws {
    guard let targetURL = url(for: relativePath) else {
      return
    }
    guard fileManager.fileExists(atPath: targetURL.path) else {
      return
    }
    try fileManager.removeItem(at: targetURL)
  }

  func url(for relativePath: String?) -> URL? {
    guard let relativePath else {
      return nil
    }

    let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      return nil
    }
    return baseDirectoryURL.appendingPathComponent(normalized, isDirectory: false)
  }

  private func removeExistingIcons(for workspaceID: UUID, preserving fileName: String) throws {
    let prefix = "\(workspaceID.uuidString)."
    let existingFiles = try fileManager.contentsOfDirectory(
      at: iconsDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    for fileURL in existingFiles where fileURL.lastPathComponent.hasPrefix(prefix) && fileURL.lastPathComponent != fileName {
      try fileManager.removeItem(at: fileURL)
    }
  }

  private func normalizedPathExtension(from sourceURL: URL) -> String {
    let ext = sourceURL.pathExtension.lowercased()
    return ext.isEmpty ? "png" : ext
  }

  private static func applicationSupportDirectory(fileManager: FileManager) throws -> URL {
    guard let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw WorkspaceIconStoreError.applicationSupportDirectoryUnavailable
    }
    return url
  }
}

enum WorkspaceIconStoreError: LocalizedError {
  case applicationSupportDirectoryUnavailable

  var errorDescription: String? {
    switch self {
    case .applicationSupportDirectoryUnavailable:
      "Diretório Application Support indisponível."
    }
  }
}
