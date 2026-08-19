import Foundation
import XCTest
import ModelShellProxy

// Bridge coreutils (toybox) smoke tests.
//
// These mirror a subset of the upstream Pipeline tests but run against the
// MSP++ bridge backend (toybox coreutils via path mapping) instead of the
// hand-written POSIX command pack. Assertions are limited to outputs the
// bridge can deterministically produce; upstream-specific behaviors (PATH
// virtualization messages, PIPESTATUS edge cases) are intentionally not
// re-asserted here.

final class MSPBridgeCoreutilsSmokeTests: MSPBridgeIntegrationTestCase {
    func testEchoProducesText() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run("echo 'bridge ok'")

        XCTAssertEqual(result.stdout, "bridge ok\n")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCatReadsSeededFile() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }
        try "hello msp++\napple\nbanana\n".write(
            to: workspace.appendingPathComponent("seed.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = await proxy.run("cat /seed.txt")

        XCTAssertEqual(result.stdout, "hello msp++\napple\nbanana\n")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testSortLinesAlphabetically() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }
        try "banana\napple\ncherry\n".write(
            to: workspace.appendingPathComponent("fruit.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = await proxy.run("sort /fruit.txt")

        XCTAssertEqual(result.stdout, "apple\nbanana\ncherry\n")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testPipelineFeedsStdoutIntoNextCommandStdin() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run("printf 'abc' | wc -c")

        // toybox wc -c emits the byte count; upstream's printf|wc pipeline
        // also yields "3\n".
        XCTAssertEqual(result.stdout, "3\n")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testHeadLimitsPipelineOutput() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        let result = await proxy.run("printf 'one\\ntwo\\nthree\\n' | head -n 2")

        XCTAssertEqual(result.stdout, "one\ntwo\n")
        XCTAssertEqual(result.exitCode, 0)
    }
}
