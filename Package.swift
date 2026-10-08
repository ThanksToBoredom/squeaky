// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Squeaky",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Squeaky",
            dependencies: ["CYara"],
            path: "Sources/Squeaky",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Vendored libyara (BSD-3), used to evaluate Apple's XProtect rules. See Sources/CYara/VENDORED.md.
        .target(
            name: "CYara",
            path: "Sources/CYara",
            exclude: ["COPYING", "VENDORED.md", "modules/module_list"],
            cSettings: [
                .define("HASH_MODULE", to: "1"),
                .define("HAVE_COMMONCRYPTO_COMMONCRYPTO_H", to: "1"),
                .define("USE_MACH_PROC", to: "1"),
                .define("NDEBUG", to: "1"),
                .headerSearchPath("."),
                .unsafeFlags(["-w"]), // third-party code: don't flood the build with its warnings
            ]
        ),
    ]
)
