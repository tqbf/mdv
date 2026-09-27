// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mdv",
    platforms: [.macOS(.v13)],
    dependencies: [
        // MarkdownUI itself is vendored — see Vendor/MarkdownUI/README.md.
        // Its own dependencies still come from the network.
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.4.0"),
        .package(url: "https://github.com/gonzalezreal/NetworkImage", from: "6.0.0"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.8.0"),
        .package(url: "https://github.com/lukilabs/beautiful-mermaid-swift", from: "1.0.4"),
    ],
    targets: [
        .executableTarget(
            name: "mdv",
            dependencies: [
                "CGrammars",
                "MarkdownUI",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "BeautifulMermaid", package: "beautiful-mermaid-swift"),
                "SwiftMath",
            ],
            path: "mdv",
            exclude: [
                "Info.plist",
                "mdv.entitlements",
                "AppIcon.icns",
                "Fonts",
                "Grammars",
                "Help.md",
                // Bundled by build.sh (downloaded, not committed).
                "mermaid.min.js",
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Vendored copy of gonzalezreal/swift-markdown-ui (markdown rendering).
        // See Vendor/MarkdownUI/README.md for the one patch it carries and why
        // it is not a package dependency.
        .target(
            name: "MarkdownUI",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "NetworkImage", package: "NetworkImage"),
            ],
            path: "Vendor/MarkdownUI/Sources/MarkdownUI"
        ),
        // Vendored copy of mgriebling/SwiftMath (LaTeX math typesetting).
        // See Vendor/SwiftMath/README.md for why it is not a package
        // dependency. Its font bundle is copied into the app by build.sh.
        .target(
            name: "SwiftMath",
            path: "Vendor/SwiftMath/Sources/SwiftMath"
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
            publicHeadersPath: "include",
            cSettings: [
                // tree-sitter's generated scanners do size_t → unsigned
                // narrowing in a few places (python, yaml). Generated code we
                // do not patch — see mdv/Grammars/README.md.
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
