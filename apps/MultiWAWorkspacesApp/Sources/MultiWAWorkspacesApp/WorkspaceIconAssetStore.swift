import AppKit
import Foundation

@MainActor
final class WorkspaceIconAssetStore {
  private let fileManager: FileManager
  private let baseDirectoryURL: URL
  private let iconsDirectoryURL: URL
  private let imageCache = NSCache<NSString, NSImage>()

  init(fileManager: FileManager = .default) throws {
    self.fileManager = fileManager

    let appSupportURL = try Self.applicationSupportDirectory(fileManager: fileManager)
    let baseDirectoryURL = appSupportURL.appendingPathComponent("com.waspaces.app", isDirectory: true)
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
    imageCache.removeObject(forKey: NSString(string: "workspace-icons/\(fileName)"))

    return "workspace-icons/\(fileName)"
  }

  func saveNormalizedPNG(_ pngData: Data, workspaceID: UUID) throws -> String {
    try fileManager.createDirectory(at: iconsDirectoryURL, withIntermediateDirectories: true)

    let fileName = "\(workspaceID.uuidString).png"
    let destinationURL = iconsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    try removeExistingIcons(for: workspaceID, preserving: fileName)

    try pngData.write(to: destinationURL, options: [.atomic])
    imageCache.removeObject(forKey: NSString(string: "workspace-icons/\(fileName)"))
    return "workspace-icons/\(fileName)"
  }

  func removeIcon(relativePath: String) throws {
    let key = normalizedCacheKey(from: relativePath)
    guard let targetURL = url(for: relativePath) else {
      return
    }
    guard fileManager.fileExists(atPath: targetURL.path) else {
      if let key {
        imageCache.removeObject(forKey: key)
      }
      return
    }
    try fileManager.removeItem(at: targetURL)
    if let key {
      imageCache.removeObject(forKey: key)
    }
  }

  func image(for relativePath: String?) -> NSImage? {
    guard let key = normalizedCacheKey(from: relativePath) else {
      return nil
    }
    if let cached = imageCache.object(forKey: key) {
      return cached
    }
    let normalizedPath = key as String
    guard let fileURL = url(for: normalizedPath), let image = NSImage(contentsOf: fileURL) else {
      imageCache.removeObject(forKey: key)
      return nil
    }
    imageCache.setObject(image, forKey: key)
    return image
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
      let relativePath = "workspace-icons/\(fileURL.lastPathComponent)"
      imageCache.removeObject(forKey: NSString(string: relativePath))
    }
  }

  private func normalizedPathExtension(from sourceURL: URL) -> String {
    let ext = sourceURL.pathExtension.lowercased()
    return ext.isEmpty ? "png" : ext
  }

  private func normalizedCacheKey(from relativePath: String?) -> NSString? {
    guard let relativePath else {
      return nil
    }
    let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      return nil
    }
    return NSString(string: normalized)
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
