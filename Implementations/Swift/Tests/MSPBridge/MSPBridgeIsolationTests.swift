import Foundation
import XCTest
import ModelShellProxy

// Bridge isolation tests: the mapping tier (toybox/git, real process on the
// physical workspace + path mapper) must prevent host paths from leaking, and
// the interception tier (embedded CPython) must route file access through the
// virtual filesystem so the interpreter cannot escape the workspace either.
//
// These are the contract that `Docs/MSP++.md` records as "两层隔离":
//   - ls /etc                 -> blocked at the mapping tier
//   - python reads /etc/passwd -> blocked at the interception tier
//   - python writes /tmp/pwn.txt -> virtualized into the workspace, no host file

final class MSPBridgeIsolationTests: MSPBridgeIntegrationTestCase {
    func testCoreutilsCannotReadHostPathEtc() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run("ls /etc")

        // The mapping tier virtualizes the filesystem: /etc does not exist in
        // the sandbox, so toybox ls reports it missing and never touches the
        // host's real /etc.
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("No such file or directory")
                || result.stderr.contains("cannot access"),
            "expected a not-found diagnostic, got: \(result.stderr)"
        )
    }

    func testPythonCannotReadHostPasswd() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run(#"python3 -c 'print(open("/etc/passwd").read())'"#)

        // The interception tier routes open() through the VFS broker; /etc/passwd
        // is not in the workspace, so Python raises FileNotFoundError.
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("FileNotFoundError")
                || result.stderr.contains("No such file or directory"),
            "expected FileNotFoundError, got: \(result.stderr)"
        )
    }

    func testPythonWriteToTmpIsVirtualizedIntoWorkspace() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run(#"python3 -c 'open("/tmp/pwn.txt","w").write("pwn")'"#)
        XCTAssertEqual(result.exitCode, 0)

        // The write succeeded at the interception tier, but it landed in the
        // workspace's virtual /tmp — the host /tmp/pwn.txt must NOT exist.
        let hostPwn = URL(fileURLWithPath: "/tmp/pwn.txt")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: hostPwn.path),
            "python write escaped the workspace to the host /tmp"
        )

        // And reading it back through the bridge returns the written content,
        // proving it was virtualized, not dropped.
        let readback = await proxy.run("cat /tmp/pwn.txt")
        XCTAssertEqual(readback.stdout, "pwn")
    }

    func testEmbeddedCPythonEvaluatesArithmetic() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run("python3 -c 'print(41 + 1)'")

        XCTAssertEqual(result.stdout, "42\n")
        XCTAssertEqual(result.exitCode, 0)
    }
}
