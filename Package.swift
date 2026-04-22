// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WASpaces",
  defaultLocalization: "pt-BR",
  platforms: [
    .macOS(.v14),
    .iOS(.v17)
  ],
  products: [
    .library(name: "WorkspaceDomain", targets: ["WorkspaceDomain"]),
    .library(name: "WorkspacePersistence", targets: ["WorkspacePersistence"]),
    .library(name: "WorkspaceSession", targets: ["WorkspaceSession"]),
    .library(name: "WorkspaceApplicationServices", targets: ["WorkspaceApplicationServices"]),
    .library(name: "WorkspaceBridgeContracts", targets: ["WorkspaceBridgeContracts"]),
    .library(name: "WorkspaceBridgeClient", targets: ["WorkspaceBridgeClient"]),
    .library(name: "WASpacesiOSCore", targets: ["WASpacesiOSCore"]),
    .executable(name: "WASpaces", targets: ["WASpacesMac"]),
    .executable(name: "WASpacesMac", targets: ["WASpacesMac"]),
    .executable(name: "WASpacesiOS", targets: ["WASpacesiOS"]),
    .executable(name: "SessionBridgeServer", targets: ["SessionBridgeServer"])
  ],
  dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.108.0"),
    .package(url: "https://github.com/vapor/fluent.git", from: "4.10.0"),
    .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0")
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
      dependencies: ["WorkspaceDomain", "WorkspacePersistence", "WorkspaceSession", "WorkspaceBridgeContracts"],
      path: "packages/WorkspaceApplicationServices/Sources/WorkspaceApplicationServices"
    ),
    .testTarget(
      name: "WorkspaceApplicationServicesTests",
      dependencies: ["WorkspaceApplicationServices", "WorkspaceDomain"],
      path: "packages/WorkspaceApplicationServices/Tests/WorkspaceApplicationServicesTests"
    ),
    .target(
      name: "WorkspaceBridgeContracts",
      path: "packages/WorkspaceBridgeContracts/Sources/WorkspaceBridgeContracts"
    ),
    .target(
      name: "WorkspaceBridgeClient",
      dependencies: ["WorkspaceBridgeContracts"],
      path: "packages/WorkspaceBridgeClient/Sources/WorkspaceBridgeClient"
    ),
    .testTarget(
      name: "WorkspaceBridgeClientTests",
      dependencies: ["WorkspaceBridgeClient"],
      path: "packages/WorkspaceBridgeClient/Tests/WorkspaceBridgeClientTests"
    ),
    .testTarget(
      name: "WorkspaceBridgeContractsTests",
      dependencies: ["WorkspaceBridgeContracts"],
      path: "packages/WorkspaceBridgeContracts/Tests/WorkspaceBridgeContractsTests"
    ),
    .target(
      name: "WASpacesiOSCore",
      dependencies: [
        "WorkspaceBridgeContracts",
        "WorkspaceBridgeClient",
        "WorkspaceDomain",
        "WorkspacePersistence",
        "WorkspaceSession",
        "WorkspaceApplicationServices"
      ],
      path: "apps/WASpacesiOS/Sources/WASpacesiOS"
    ),
    .executableTarget(
      name: "WASpacesMac",
      dependencies: ["WorkspaceDomain", "WorkspacePersistence", "WorkspaceSession", "WorkspaceApplicationServices", "WorkspaceBridgeContracts", "WorkspaceBridgeClient"],
      path: "apps/MultiWAWorkspacesApp/Sources/MultiWAWorkspacesApp"
    ),
    .testTarget(
      name: "WASpacesMacTests",
      dependencies: ["WASpacesMac"],
      path: "apps/MultiWAWorkspacesApp/Tests/MultiWAWorkspacesAppTests"
    ),
    .executableTarget(
      name: "WASpacesiOS",
      dependencies: ["WASpacesiOSCore", "WorkspaceBridgeContracts"],
      path: "apps/WASpacesiOS/Sources/WASpacesiOSCLI"
    ),
    .testTarget(
      name: "WASpacesiOSTests",
      dependencies: ["WASpacesiOSCore", "WorkspaceBridgeContracts"],
      path: "apps/WASpacesiOS/Tests/WASpacesiOSTests"
    ),
    .executableTarget(
      name: "SessionBridgeServer",
      dependencies: [
        "WorkspaceBridgeContracts",
        .product(name: "Vapor", package: "vapor"),
        .product(name: "Fluent", package: "fluent"),
        .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver")
      ],
      path: "bridge/SessionBridgeServer/Sources/SessionBridgeServer"
    ),
    .testTarget(
      name: "SessionBridgeServerTests",
      dependencies: [
        "SessionBridgeServer",
        .product(name: "XCTVapor", package: "vapor")
      ],
      path: "bridge/SessionBridgeServer/Tests/SessionBridgeServerTests"
    )
  ]
)
