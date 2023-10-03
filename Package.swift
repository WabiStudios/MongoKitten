// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MongoKitten",
    platforms: [
      .macOS(.v13),
      .iOS(.v16),
      .tvOS(.v12),
      .visionOS(.v1),
      .watchOS(.v4),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "MongoKitten",
            targets: ["MongoKitten", "MongoClient"]),
        .library(
            name: "Meow",
            targets: ["Meow"]),
        .library(
            name: "MongoClient",
            targets: ["MongoClient"]),
        .library(
            name: "MongoCore",
            targets: ["MongoCore"]),
    ],
    dependencies: [
        // ✏️
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    
        // 📈
        .package(url: "https://github.com/apple/swift-metrics.git", "1.0.0" ..< "3.0.0"),        
        
        // 💾
        .package(url: "https://github.com/orlandos-nl/BSON.git", from: "7.0.28"),
        
        // 🚀
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),

        // 📚
        .package(url: "https://github.com/orlandos-nl/DNSClient.git", from: "2.0.0"),
        
        // 🔑
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "_MongoKittenCrypto",
            dependencies: []),
        .target(
            name: "MongoCore",
            dependencies: [
                .product(name: "BSON", package: "BSON"),
                "_MongoKittenCrypto",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]),
        .target(
            name: "MongoKittenCore",
            dependencies: ["MongoClient"]
        ),
        .target(
            name: "MongoKitten",
            dependencies: ["MongoClient", "MongoKittenCore", .product(name: "NIOCore", package: "swift-nio")]
        ),
        .target(
            name: "Meow",
            dependencies: ["MongoKitten"]),
        .target(
            name: "MongoClient",
            dependencies: [
                "MongoCore",
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "DNSClient", package: "DNSClient")
            ]
        ),
        .testTarget(
            name: "MongoCoreTests",
            dependencies: ["MongoCore"]),
        .testTarget(
            name: "MongoKittenTests",
            dependencies: ["MongoKitten"]),
        // TODO: Reimplement these tests
//        .testTarget(
//            name: "MeowTests",
//            dependencies: ["Meow"]),
    ]
)
