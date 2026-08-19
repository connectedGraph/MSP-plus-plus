// swift-tools-version: 5.9

import PackageDescription

// MSP++ — trimmed manifest for the bridge build.
//
// Removed vs upstream: swift-cgit2 / MSPGit (git is bridged as a real external
// binary, not embedded via libgit2), and the iOS-only / chat / validator /
// apply_patch-bridge targets. Kept: shell + virtual FS + external-runner +
// embedded-python + MSPBridge. Zero external network dependencies.

let package = Package(
    name: "ModelShellProxy",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "ModelShellProxy", targets: ["ModelShellProxy"]),
        .library(name: "MSPCore", targets: ["MSPCore"]),
        .library(name: "MSPShellLanguage", targets: ["MSPShellLanguage"]),
        .library(name: "MSPShellExpansion", targets: ["MSPShellExpansion"]),
        .library(name: "MSPShell", targets: ["MSPShell"]),
        .library(name: "MSPCommandKit", targets: ["MSPCommandKit"]),
        .library(name: "MSPExternalRunner", targets: ["MSPExternalRunner"]),
        .library(name: "MSPAgentBridge", targets: ["MSPAgentBridge"]),
        .library(name: "MSPPOSIXCore", targets: ["MSPPOSIXCore"]),
        .library(name: "MSPPythonRuntime", targets: ["MSPPythonRuntime"]),
        .library(name: "MSPPythonEmbeddedRuntime", targets: ["MSPPythonEmbeddedRuntime"]),
        .library(name: "MSPApple", targets: ["MSPApple"]),
        .library(name: "MSPBridge", targets: ["MSPBridge"]),
        .executable(name: "mspxx-smoke", targets: ["MSPBridgeSmoke"]),
    ],
    targets: [
        .target(
            name: "MSPCore",
            path: "Sources/MSPCore"
        ),
        .target(
            name: "MSPShellLanguage",
            path: "Sources/MSPShellLanguage",
            sources: ["AST", "Conversion", "Lexer", "Parsed", "Parser", "Reconstruction", "Syntax", "Values"]
        ),
        .target(
            name: "MSPShellExpansion",
            dependencies: ["MSPShellLanguage"],
            path: "Sources/MSPShellExpansion",
            sources: ["API", "Arithmetic", "Brace", "Effects", "FieldSplitting", "Parameters", "Pattern", "Words"]
        ),
        .target(
            name: "MSPShell",
            dependencies: ["MSPShellLanguage", "MSPShellExpansion"],
            path: "Sources/MSPShell"
        ),
        .target(
            name: "MSPCommandKit",
            dependencies: ["MSPCore"],
            path: "Sources/MSPCommandKit"
        ),
        .target(
            name: "MSPExternalRunner",
            dependencies: ["MSPCore"],
            path: "Sources/MSPExternalRunner"
        ),
        .target(
            name: "MSPAgentBridge",
            dependencies: ["MSPCore"],
            path: "Sources",
            exclude: [
                "MSPApple",
                "MSPChat",
                "MSPChatCommands",
                "MSPAgentChatStore",
                "MSPChatValidatorCLI",
                "MSPCodexApplyPatchRuntime",
                "MSPCommandKit",
                "MSPCore",
                "MSPExternalRunner",
                "MSPGit",
                "MSPPOSIXCore",
                "MSPPtySupport",
                "MSPPythonEmbeddedRuntime",
                "MSPPythonRuntime",
                "MSPShell",
                "MSPShellExpansion",
                "MSPShellLanguage",
                "ModelShellProxy",
                "Tools/Vendor"
            ],
            sources: [
                "MSPAgentBridge/Capabilities",
                "MSPAgentBridge/Compaction",
                "MSPAgentBridge/JSON",
                "MSPAgentBridge/Model",
                "MSPAgentBridge/Model/ResponsesStreaming",
                "MSPAgentBridge/Rendering",
                "MSPAgentBridge/Request",
                "MSPAgentBridge/Runtime",
                "Tools/MSP/exec_command/Contract",
                "Tools/MSP/exec_command/Runtime",
                "Tools/MSP/apply_patch/Contract",
                "Tools/MSP/apply_patch/Runtime",
                "Tools/MSP/write_stdin/Contract",
                "Tools/MSP/write_stdin/Runtime",
                "Tools/MSP/update_plan/Contract",
                "Tools/MSP/update_plan/Runtime"
            ]
        ),
        .target(
            name: "MSPPOSIXCore",
            dependencies: ["MSPCore"],
            path: "Sources/MSPPOSIXCore",
            sources: ["Commands", "Registry", "Support"]
        ),
        .target(
            name: "MSPPythonRuntime",
            dependencies: ["MSPCore"],
            path: "Sources/MSPPythonRuntime"
        ),
        .target(
            name: "MSPPythonEmbeddedRuntime",
            dependencies: ["MSPCore", "MSPPythonRuntime"],
            path: "Sources/MSPPythonEmbeddedRuntime",
            sources: ["CPython", "Runtime"]
        ),
        .target(
            name: "MSPApple",
            dependencies: ["MSPCore"],
            path: "Sources/MSPApple"
        ),
        .target(
            name: "MSPPtySupport",
            path: "Sources/MSPPtySupport",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MSPBridge",
            dependencies: ["MSPCore", "MSPExternalRunner", "MSPPythonRuntime", "MSPPythonEmbeddedRuntime"],
            path: "Sources/MSPBridge"
        ),
        .executableTarget(
            name: "MSPBridgeSmoke",
            dependencies: ["ModelShellProxy", "MSPBridge", "MSPApple"],
            path: "Sources/MSPBridgeSmoke"
        ),
        .target(
            name: "ModelShellProxy",
            dependencies: [
                "MSPCore",
                "MSPShell",
                "MSPCommandKit",
                "MSPExternalRunner",
                "MSPAgentBridge",
                "MSPPOSIXCore",
                "MSPApple",
                "MSPPtySupport"
            ],
            path: "Sources/ModelShellProxy"
        ),
        .testTarget(
            name: "MSPBridgeTests",
            dependencies: [
                "ModelShellProxy",
                "MSPBridge",
                "MSPApple",
                "MSPAgentBridge"
            ],
            path: "Tests/MSPBridge"
        )
    ]
)
