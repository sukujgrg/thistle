// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
  name: "thistle",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .executable(name: "Thistle", targets: ["ThistleMacOS"]),
    .executable(name: "ThistleEngine", targets: ["ThistleEngine"]),
    .executable(name: "ThistleUpdater", targets: ["ThistleUpdater"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/containerization.git", from: "0.30.0"),
    .package(url: "https://github.com/apple/swift-system.git", from: "1.4.0"),
  ],
  targets: [
    .target(
      name: "ThistleSupport"
    ),
    .executableTarget(
      name: "ThistleEngine",
      dependencies: [
        "ThistleSupport",
        .product(name: "Containerization", package: "containerization"),
        .product(name: "ContainerizationArchive", package: "containerization"),
        .product(name: "ContainerizationEXT4", package: "containerization"),
        .product(name: "ContainerizationExtras", package: "containerization"),
        .product(name: "SystemPackage", package: "swift-system"),
      ]
    ),
    .executableTarget(
      name: "ThistleMacOS",
      dependencies: [
        "ThistleSupport"
      ]
    ),
    .executableTarget(
      name: "ThistleUpdater",
      dependencies: [
        "ThistleSupport"
      ]
    ),
    .testTarget(
      name: "ThistleSupportTests",
      dependencies: [
        "ThistleSupport"
      ]
    ),
  ]
)
