// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "CHIBI",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "CHIBI", targets: ["CHIBIApp"])
  ],
  targets: [
    .executableTarget(
      name: "CHIBIApp",
      path: "Sources/CHIBIApp",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "CHIBIAppTests",
      dependencies: ["CHIBIApp"],
      path: "Tests/CHIBIAppTests"
    ),
  ]
)
