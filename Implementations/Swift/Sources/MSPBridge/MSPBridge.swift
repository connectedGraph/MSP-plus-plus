import Foundation
import MSPCore
import MSPExternalRunner
import MSPPythonRuntime
import MSPPythonEmbeddedRuntime

// MSP++ bridge profile.
//
// Instead of MSP's hand-written Swift reimplementation of the POSIX command
// surface, MSP++ backs the command surface with REAL runtimes, all routed
// through the shared external-command infrastructure:
//
//   - coreutils -> toybox (permissive BSD-0, single multi-call binary; each
//                  applet registered as an external command via its
//                  `make install_flat` symlink, so argv[0] basename dispatches)
//   - git       -> real git binary
//   - python    -> embedded CPython (MSPPythonEmbeddedRuntime), whose file
//                  access is intercepted by MSPPythonVirtualFileSystemBroker
//
// coreutils + git run at the MAPPING tier (path mapper + output sanitizer:
// the process operates on the physical workspace dir, output re-virtualized).
// python runs at the INTERCEPTION tier (in-process, file layer virtualized).
// This is the "统一桥接 broker" — one `enable(.bridge)` wires all three.

public struct MSPBridgeConfiguration {
    /// Directory holding the built toybox binary AND its applet symlinks
    /// (from `make install_flat PREFIX=<dir>`): <dir>/toybox, <dir>/ls, ...
    public var toyboxBinDirectoryURL: URL
    /// Absolute path to the real `git` binary (e.g. /usr/bin/git).
    public var gitURL: URL
    /// How to load libpython for the embedded interpreter.
    public var pythonLibrary: MSPCPythonLibrary
    /// Optional PYTHONHOME (stdlib location); defaults to the lib's own home.
    public var pythonHomeURL: URL?
    /// Extra environment applied to every bridged external command.
    public var environment: [String: String]
    /// Pre-supplied toybox applet list. When nil, auto-enumerated once via
    /// `<toyboxBin>/toybox --list`.
    public var toyboxApplets: [String]?

    public init(
        toyboxBinDirectoryURL: URL,
        gitURL: URL,
        pythonLibrary: MSPCPythonLibrary,
        pythonHomeURL: URL? = nil,
        environment: [String: String] = [:],
        toyboxApplets: [String]? = nil
    ) {
        self.toyboxBinDirectoryURL = toyboxBinDirectoryURL
        self.gitURL = gitURL
        self.pythonLibrary = pythonLibrary
        self.pythonHomeURL = pythonHomeURL
        self.environment = environment
        self.toyboxApplets = toyboxApplets
    }
}

public enum MSPBridge {
    /// Shell control builtins handled natively by the runtime — the bridge must
    /// never shadow these with an external command.
    static let reservedNames: Set<String> = [
        "cd", "exit", "export", "set", "unset", "shift", "readonly", "trap",
        "umask", "hash", "type", "command", "return", "break", "continue",
        ".", ":", "source", "local",
    ]

    /// Host-mutating / privileged toybox applets that must never be exposed
    /// as sandbox commands: these run as REAL host processes via path mapping,
    /// so `reboot`/`mount`/`su` would touch the actual host.
    static let denylist: Set<String> = [
        "mount", "umount", "swapon", "swapoff", "insmod", "rmmod", "modinfo",
        "lsmod", "reboot", "poweroff", "halt", "su", "login", "nologin",
        "chroot", "nsenter", "unshare", "pivot_root", "switch_root",
        "ifconfig", "mkswap", "mkpasswd", "taskset", "ionice", "iorenice",
        "rtcwake", "sfdisk", "mdev", "init", "poweroff", "shutdown",
    ]

    /// Build the MSP++ bridge profile. All three runtimes register through the
    /// existing path mapper + output sanitizer; python additionally gets the
    /// embedded VFS broker.
    public static func bridgeProfile(
        _ configuration: MSPBridgeConfiguration
    ) throws -> MSPProfile {
        MSPProfile(name: "bridge") { registry in
            try registerCoreutils(into: registry, configuration: configuration)
            try registerGit(into: registry, configuration: configuration)
            try registerPython(into: registry, configuration: configuration)
        }
    }

    /// Enumerate toybox applets. NOTE: bare `toybox` (no args) prints the
    /// command list, whitespace-separated and 80-col wrapped; `--list` is NOT
    /// a valid flag (toybox's multiplexer rejects it as an unknown command).
    public static func enumerateToyboxApplets(
        toyboxBinaryURL: URL
    ) throws -> [String] {
        let process = Process()
        process.executableURL = toyboxBinaryURL
        process.arguments = []
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - coreutils (mapping tier)

    private static func registerCoreutils(
        into registry: MSPCommandRegistry,
        configuration: MSPBridgeConfiguration
    ) throws {
        let toyboxURL = configuration.toyboxBinDirectoryURL
            .appendingPathComponent("toybox")
        let applets = try configuration.toyboxApplets
            ?? enumerateToyboxApplets(toyboxBinaryURL: toyboxURL)
        for applet in applets {
            guard !reservedNames.contains(applet) else { continue }
            guard !denylist.contains(applet) else { continue }
            guard registry.command(named: applet) == nil else { continue }
            // argv[0] basename == applet name via the install_flat symlink, so
            // toybox's multi-call dispatch picks the right applet.
            let appletURL = configuration.toyboxBinDirectoryURL
                .appendingPathComponent(applet)
            try registry.registerExternalCommand(
                applet,
                runner: MSPHostProcessExternalRunner(
                    executableURL: appletURL,
                    extraEnvironment: configuration.environment
                )
            )
        }
    }

    // MARK: - git (mapping tier)

    private static func registerGit(
        into registry: MSPCommandRegistry,
        configuration: MSPBridgeConfiguration
    ) throws {
        try registry.registerExternalCommand(
            "git",
            runner: MSPHostProcessExternalRunner(
                executableURL: configuration.gitURL,
                extraEnvironment: configuration.environment
            )
        )
    }

    // MARK: - python (interception tier)

    private static func registerPython(
        into registry: MSPCommandRegistry,
        configuration: MSPBridgeConfiguration
    ) throws {
        let engine = try MSPCPythonEngine(
            library: configuration.pythonLibrary,
            pythonHomeURL: configuration.pythonHomeURL
        )
        let runtime = MSPPythonEmbeddedRuntime(engine: engine)
        try MSPPythonCommandPack(runtime: runtime)
            .registerCommands(into: registry)
    }
}
