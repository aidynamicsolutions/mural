// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuralCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MuralCore", targets: ["MuralCore"])],
    dependencies: [
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC.git",
                 revision: "1d8105a0f7199c90af722bff62728050c858e777")
    ],
    targets: [
        .target(name: "MuralCore", dependencies: [.product(name: "OpenCC", package: "swiftyopencc")], path: "Core", resources: [.process("Resources/tts-corpus.json"), .copy("Resources/opencc-notices.txt")]),
        .testTarget(name: "MuralCoreTests", dependencies: ["MuralCore"], path: "Tests")
    ]
)
