import Foundation
import XCTest
import MSPBridge
import MSPApple
import MSPPythonEmbeddedRuntime
import ModelShellProxy

// Bridge test support: builds an MSPBridgeConfiguration from environment
// variables (or WSL defaults) and a ModelShellProxy wired to the bridge
// profile, so each test gets a real toybox + git + embedded-CPython sandbox.
//
// Env overrides:
//   MSP_BRIDGE_TOYBOX_DIR  (default ~/msp-build/toybox-bin)
//   MSP_BRIDGE_GIT         (default /usr/bin/git)
//   MSP_BRIDGE_LIBPYTHON   (default /usr/lib/x86_64-linux-gnu/libpython3.14.so)
//
// If the toybox directory is absent, tests that need the bridge are skipped
// (XCTSkip) rather than failing — so the suite is safe to evaluate on a host
// that has not built toybox yet.

enum MSPBridgeTestSupport {
    static var toyboxBinDirectoryURL: URL {
        let path = ProcessInfo.processInfo.environment["MSP_BRIDGE_TOYBOX_DIR"]
            ?? "/home/rap/msp-build/toybox-bin"
        return URL(fileURLWithPath: path)
    }

    static var gitURL: URL {
        let path = ProcessInfo.processInfo.environment["MSP_BRIDGE_GIT"]
            ?? "/usr/bin/git"
        return URL(fileURLWithPath: path)
    }

    static var pythonLibrary: MSPCPythonLibrary {
        let path = ProcessInfo.processInfo.environment["MSP_BRIDGE_LIBPYTHON"]
            ?? "/usr/lib/x86_64-linux-gnu/libpython3.14.so"
        return .path(URL(fileURLWithPath: path))
    }

    /// True when the toybox binary directory actually exists, i.e. the host
    /// has a built bridge runtime. Tests call this to decide whether to skip.
    static var bridgeRuntimeAvailable: Bool {
        FileManager.default.fileExists(atPath: toyboxBinDirectoryURL.path)
    }

    static func makeConfiguration() -> MSPBridgeConfiguration {
        MSPBridgeConfiguration(
            toyboxBinDirectoryURL: toyboxBinDirectoryURL,
            gitURL: gitURL,
            pythonLibrary: pythonLibrary
        )
    }

    /// Build a fresh proxy on a throwaway workspace with the bridge profile
    /// enabled. Throws if the bridge runtime is missing — callers should
    /// gate on `bridgeRuntimeAvailable` (or call `tryRequireBridge`) first.
    static func makeBridgeProxy(workspaceURL: URL) throws -> ModelShellProxy {
        let workspace = try MSPAppleWorkspace(rootURL: workspaceURL)
        let proxy = ModelShellProxy(configuration: MSPConfiguration(workspace: workspace))
        try proxy.enable(MSPBridge.bridgeProfile(makeConfiguration()))
        return proxy
    }
}

class MSPBridgeIntegrationTestCase: XCTestCase {
    /// A temporary workspace directory unique to this test.
    func makeTemporaryURL(_ name: String = UUID().uuidString) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MSPBridgeTests", isDirectory: true)
        return root.appendingPathComponent(name)
    }

    func removeTemporaryURL(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Skip the calling test when the bridge runtime is not installed on the
    /// host. Use at the top of any test that needs real toybox/git/python.
    func requireBridgeRuntime() throws {
        try XCTSkipUnless(
            MSPBridgeTestSupport.bridgeRuntimeAvailable,
            "Bridge runtime (toybox) not found at \(MSPBridgeTestSupport.toyboxBinDirectoryURL.path); set MSP_BRIDGE_TOYBOX_DIR or build toybox."
        )
    }

    /// Convenience: build a bridge proxy on a fresh temp workspace, with
    /// `requireBridgeRuntime()` gating already applied.
    func makeBridgeProxy(
        name: String = UUID().uuidString
    ) throws -> (proxy: ModelShellProxy, workspace: URL) {
        try requireBridgeRuntime()
        let workspace = makeTemporaryURL(name)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        let proxy = try MSPBridgeTestSupport.makeBridgeProxy(workspaceURL: workspace)
        return (proxy, workspace)
    }
}
