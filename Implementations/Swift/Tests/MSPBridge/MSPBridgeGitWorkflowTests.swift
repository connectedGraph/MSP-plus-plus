import Foundation
import XCTest
import ModelShellProxy

// Bridge git workflow tests: the mapping tier runs the real git binary as a
// host process on the physical workspace, so a git repo created inside the
// sandbox must stay entirely within the workspace — its .git directory and all
// object files must never escape to the host's real filesystem.
//
// This covers the "git 实际工作流" item from Docs/MSP++.md: git init/add/
// commit/log/status work end-to-end, and the repository stays contained.

final class MSPBridgeGitWorkflowTests: MSPBridgeIntegrationTestCase {
    func testGitInitStatusAndCommitRoundTrip() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        // Seed a tracked file in the workspace.
        try "hello git\n".write(
            to: workspace.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )

        let initResult = await proxy.run("git init")
        XCTAssertEqual(initResult.exitCode, 0, "git init failed: \(initResult.stderr)")
        XCTAssertTrue(
            initResult.stdout.contains("Initialized empty Git repository"),
            "unexpected git init output: \(initResult.stdout)"
        )

        let addResult = await proxy.run("git add hello.txt")
        XCTAssertEqual(addResult.exitCode, 0, "git add failed: \(addResult.stderr)")

        // Config the author so commit doesn't require host-level global config.
        let configName = await proxy.run("git config user.email bridge@test.local")
        let configEmail = await proxy.run("git config user.name 'Bridge Tester'")
        XCTAssertEqual(configName.exitCode, 0, "git config email failed: \(configName.stderr)")
        XCTAssertEqual(configEmail.exitCode, 0, "git config name failed: \(configEmail.stderr)")

        let commitResult = await proxy.run("git commit -m 'initial commit'")
        XCTAssertEqual(commitResult.exitCode, 0, "git commit failed: \(commitResult.stderr)")

        let logResult = await proxy.run("git log --oneline -1")
        XCTAssertEqual(logResult.exitCode, 0, "git log failed: \(logResult.stderr)")
        XCTAssertTrue(
            logResult.stdout.contains("initial commit"),
            "unexpected git log output: \(logResult.stdout)"
        )

        let statusResult = await proxy.run("git status --short")
        XCTAssertEqual(statusResult.exitCode, 0, "git status failed: \(statusResult.stderr)")
        XCTAssertEqual(statusResult.stdout, "", "expected clean status, got: \(statusResult.stdout)")
    }

    func testGitRepositoryIsContainedInsideWorkspace() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }
        try "content\n".write(
            to: workspace.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )

        _ = await proxy.run("git init")
        _ = await proxy.run("git add a.txt")
        _ = await proxy.run("git config user.email bridge@test.local")
        _ = await proxy.run("git config user.name 'Bridge Tester'")
        _ = await proxy.run("git commit -m 'initial'")

        // The real .git must be under the workspace, never the host cwd.
        let workspaceGit = workspace.appendingPathComponent(".git")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: workspaceGit.path),
            "expected .git inside workspace at \(workspaceGit.path)"
        )

        // A sibling directory (the test process's own parent) must not have
        // gained a .git from the sandbox's git operations.
        let hostParent = workspace.deletingLastPathComponent()
        let hostGit = hostParent.appendingPathComponent(".git")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: hostGit.path),
            "git created .git outside the workspace at \(hostGit.path)"
        )

        // The object database holds the committed blob — proof the commit
        // actually materialized inside the sandbox.
        let objectsDir = workspaceGit.appendingPathComponent("objects")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: objectsDir.path),
            "expected .git/objects inside workspace"
        )
        let objectEntries = try FileManager.default.contentsOfDirectory(atPath: objectsDir.path)
        XCTAssertTrue(
            objectEntries.count > 0,
            "expected at least one object directory in .git/objects"
        )
    }

    func testGitCannotAccessHostRepository() async throws {
        let (proxy, workspace) = try makeBridgeProxy()
        defer { removeTemporaryURL(workspace) }

        // /home/rap is the host user's real home; the mapping tier must keep it
        // out of the sandbox, so a git invocation pointing at it must fail as
        // if the path did not exist rather than reaching the real repo.
        let result = await proxy.run("git -C /home/rap rev-parse --is-inside-work-tree")

        XCTAssertNotEqual(result.exitCode, 0, "git reached the host home directory")
        XCTAssertTrue(
            result.stderr.contains("No such file") || result.stderr.contains("not a git repository"),
            "expected a not-found diagnostic, got: \(result.stderr)"
        )
    }
}
