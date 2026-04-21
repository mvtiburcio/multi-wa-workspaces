// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MultiWAWorkspaces",
  defaultLocalization: "pt-BR",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "WorkspaceDomain", targets: ["WorkspaceDomain"]),
    .library(name: "WorkspacePersistence", targets: ["WorkspacePersistence"]),
    .library(name: "WorkspaceSession", targets: ["WorkspaceSession"]),
    .library(name: "WorkspaceApplicationServices", targets: ["WorkspaceApplicationServices"]),
    .executable(name: "MultiWAWorkspacesApp", targets: ["MultiWAWorkspacesApp"])
  ],
  targets: [
    .target(
      name: "WorkspaceDomain",
      path: "packages/WorkspaceDomain/Sources/WorkspaceDomain"
    ),
    .testTarget(
      name: "WorkspaceDomainTests",
      dependencies: ["WorkspaceDomain"],
      path: "packages/WorkspaceDomain/Tests/WorkspaceDomainTests"
    ),
    .target(
      name: "WorkspacePersistence",
      dependencies: ["WorkspaceDomain"],
      path: "packages/WorkspacePersistence/Sources/WorkspacePersistence"
    ),
    .testTarget(
      name: "WorkspacePersistenceTests",
      dependencies: ["WorkspacePersistence", "WorkspaceDomain"],
      path: "packages/WorkspacePersistence/Tests/WorkspacePersistenceTests"
    ),
    .target(
      name: "WorkspaceSession",
      dependencies: ["WorkspaceDomain"],
      path: "packages/WorkspaceSession/Sources/WorkspaceSession"
    ),
    .testTarget(
      name: "WorkspaceSessionTests",
      dependencies: ["WorkspaceSession", "WorkspaceDomain"],
      path: "packages/WorkspaceSession/Tests/WorkspaceSessionTests"
    ),
    .target(
      name: "WorkspaceApplicationServices",
      dependencies: ["WorkspaceDomain", "WorkspacePersistence", "WorkspaceSession"],
      path: "packages/WorkspaceApplicationServices/Sources/WorkspaceApplicationServices"
    ),
    .testTarget(
      name: "WorkspaceApplicationServicesTests",
      dependencies: ["WorkspaceApplicationServices", "WorkspaceDomain"],
      path: "packages/WorkspaceApplicationServices/Tests/WorkspaceApplicationServicesTests"
    ),
    .executableTarget(
      name: "MultiWAWorkspacesApp",
      dependencies: ["WorkspaceDomain", "WorkspacePersistence", "WorkspaceSession", "WorkspaceApplicationServices"],
      path: "apps/MultiWAWorkspacesApp/Sources/MultiWAWorkspacesApp"
    ),
    .testTarget(
      name: "MultiWAWorkspacesAppTests",
      dependencies: ["MultiWAWorkspacesApp"],
      path: "apps/MultiWAWorkspacesApp/Tests/MultiWAWorkspacesAppTests"
    )
  ]
)
