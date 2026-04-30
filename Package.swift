// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mdv",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "mdv",
            dependencies: [
                "CGrammars",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
            ],
            path: "mdv",
            exclude: [
                "Info.plist",
                "mdv.entitlements",
                "AppIcon.icns",
                "Fonts",
                "Grammars",
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "CGrammars",
            path: "mdv/Grammars",
            exclude: [
                "README.md",
                "Grammars-Bridging.h",
                "bash-highlights.scm",
                "c-highlights.scm",
                "go-highlights.scm",
                "javascript-highlights.scm",
                "python-highlights.scm",
                "ruby-highlights.scm",
                "rust-highlights.scm",
                "toml-highlights.scm",
                "yaml-highlights.scm",
                "yaml/schema.generated.cc",
            ],
            sources: [
                "bash/parser.c", "bash/scanner.c",
                "c/parser.c",
                "go/parser.c",
                "javascript/parser.c", "javascript/scanner.c",
                "python/parser.c", "python/scanner.c",
                "ruby/parser.c", "ruby/scanner.c",
                "rust/parser.c", "rust/scanner.c",
                "toml/parser.c", "toml/scanner.c",
                "yaml/parser.c", "yaml/scanner.cc",
            ],
            publicHeadersPath: "include"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
