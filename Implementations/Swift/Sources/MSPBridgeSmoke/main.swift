import Foundation
import ModelShellProxy
import MSPBridge
import MSPApple

// MSP++ bridge smoke test: build the bridge profile (toybox coreutils + git +
// embedded python) on a fresh proxy and run real commands through it.

@main
struct MSPBridgeSmoke {
    static func main() async throws {
        let wsDir = URL(fileURLWithPath: "/tmp/mspxx-ws")
        try? FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        try? "hello msp++\napple\nbanana\n".write(
            to: wsDir.appendingPathComponent("seed.txt"),
            atomically: true,
            encoding: .utf8
        )

        let config = MSPBridgeConfiguration(
            toyboxBinDirectoryURL: URL(fileURLWithPath: "/home/rap/msp-build/toybox-bin"),
            gitURL: URL(fileURLWithPath: "/usr/bin/git"),
            pythonLibrary: .path(URL(fileURLWithPath: "/usr/lib/x86_64-linux-gnu/libpython3.14.so"))
        )
        let workspace = try MSPAppleWorkspace(rootURL: wsDir)
        let proxy = ModelShellProxy(configuration: MSPConfiguration(workspace: workspace))
        try proxy.enable(MSPBridge.bridgeProfile(config))

        let commands = [
            "ls /",
            "cat /seed.txt",
            "echo 'bridge ok'",
            "sort /seed.txt",
            "python3 -c 'print(41 + 1)'",
            "git --version",
            // containment checks
            "ls /etc",
            "python3 -c 'print(open(\"/etc/passwd\").read())'",
            "python3 -c 'open(\"/tmp/pwn.txt\",\"w\").write(\"pwn\")'",
        ]
        for cmd in commands {
            let r = await proxy.run(cmd)
            print("$ \(cmd)  [exit \(r.exitCode)]")
            let out = String(decoding: r.stdoutData, as: UTF8.self)
            if !out.isEmpty { print(out, terminator: out.hasSuffix("\n") ? "" : "\n") }
            let err = String(decoding: r.stderrData, as: UTF8.self)
            if !err.isEmpty { print("  [stderr] \(err)", terminator: err.hasSuffix("\n") ? "" : "\n") }
        }
    }
}
