// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiteRTLMApple",
    platforms: [
        .iOS(.v13),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "LiteRTLMApple",
            targets: ["LiteRTLMApple"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "LiteRTLMEngineCPU",
            path: "Artifacts/LiteRTLMEngineCPU.xcframework"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            path: "Artifacts/GemmaModelConstraintProvider.xcframework"
        ),
        .binaryTarget(
            name: "LiteRtMetalAccelerator",
            path: "Artifacts/LiteRtMetalAccelerator.xcframework"
        ),
        .binaryTarget(
            name: "LiteRtTopKMetalSampler",
            path: "Artifacts/LiteRtTopKMetalSampler.xcframework"
        ),
        .target(
            name: "LiteRTLMApple",
            dependencies: [
                "LiteRTLMEngineCPU",
                "GemmaModelConstraintProvider",
                "LiteRtMetalAccelerator",
                "LiteRtTopKMetalSampler",
            ],
            path: "Sources/LiteRTLMApple",
            publicHeadersPath: "include"
        ),
    ]
)
