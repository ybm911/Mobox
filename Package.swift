// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingyiTranslate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LingyiTranslate", targets: ["LingyiTranslate"])
    ],
    targets: [
        .executableTarget(
            name: "LingyiTranslate",
            path: ".",
            exclude: ["README.md", "script", ".codex", ".gitignore", "dist", "outputs", "Bob_Translate_Golden_Gate-60a42f51be.icns"],
            resources: [.copy("Resources/AppIcon.icns")]
        )
    ]
)
