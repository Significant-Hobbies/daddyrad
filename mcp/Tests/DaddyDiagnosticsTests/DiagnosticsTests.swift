import Foundation
import MCP
import PerformanceCore
@testable import DaddyDiagnostics
import XCTest

final class DiagnosticsTests: XCTestCase {
    func testStartupScopeRejectsImplicitHomeBroadRootsAndSymlinks() throws {
        XCTAssertThrowsError(try Configuration.parse(["--context-project", "/tmp"]))
        XCTAssertThrowsError(try Configuration.parse(["--storage-root", "/"]))
        XCTAssertThrowsError(try Configuration.parse(["--storage-root", "/Users"]))
        XCTAssertThrowsError(try Configuration.parse(["--storage-root"]))
        let temporary = FileManager.default.temporaryDirectory.path
        let canonical = temporary.hasPrefix("/var/") ? "/private" + temporary : temporary
        let root = URL(fileURLWithPath: canonical).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside")
        let alias = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.deletingLastPathComponent())
        XCTAssertEqual(try PathScope.require(root.appendingPathComponent("safe").path, within: [root]).lastPathComponent, "safe")
        XCTAssertThrowsError(try PathScope.require(outside.path, within: [root]))
        XCTAssertThrowsError(try PathScope.require(root.path + "/../outside", within: [root]))
        XCTAssertThrowsError(try PathScope.require(alias.appendingPathComponent("outside").path, within: [root]))
        XCTAssertThrowsError(try PathScope.root(alias.path))
        XCTAssertThrowsError(try PathScope.require(root.appendingPathComponent(".env.production").path, within: [root]))
        XCTAssertThrowsError(try PathScope.require(root.appendingPathComponent(".ssh/config").path, within: [root]))
    }

    func testDeniedToolsAndScopesReturnToolErrorsWithoutFallbackReads() async {
        let service = Diagnostics(configuration: Configuration())
        for (name, args) in [("run_shell", ["command": Value.string("anything")]),
                             ("context_skills", [:]), ("storage_analyze", ["path": Value.string("/Users")]),
                             ("performance_snapshot", ["limit": Value.int(1000)]),
                             ("daddy_capabilities", ["unknown": Value.bool(true)])] {
            let result = await service.call(name, arguments: args)
            XCTAssertEqual(result.isError, true)
        }
    }

    func testRoutingKeepsFirstMatchAndDisabledFallbackAndDoesNotEchoQueries() async throws {
        let service = Diagnostics(configuration: Configuration())
        let rules: Value = .array([
            .object(["id": .string(UUID().uuidString), "pattern": "example.com", "target": .object(["browser": "chrome", "profile": "Profile 1"])]),
            .object(["id": .string(UUID().uuidString), "pattern": "*.example.com", "target": .object(["browser": "safari", "profile": ""])]),
        ])
        var cfg: [String: Value] = ["enabled": true, "rules": rules, "fallback": .object(["browser": "safari", "profile": ""])]
        let result = await service.call("browser_explain_route", arguments: ["url": "https://sub.example.com/path?private_query=hidden", "config": .object(cfg)])
        XCTAssertEqual(result.isError, false)
        let data = try JSONEncoder().encode(result)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private_query"))
        guard case .object(let payload) = result.structuredContent, case .object(let target) = payload["target"] else { return XCTFail("Missing routing result") }
        XCTAssertEqual(payload["matchedRuleIndex"], .int(0))
        XCTAssertEqual(payload["otherMatchingRuleIndices"], .array([.int(1)]))
        XCTAssertEqual(target["browser"], "chrome")
        cfg["enabled"] = false
        let disabled = await service.call("browser_explain_route", arguments: ["url": "https://example.com", "config": .object(cfg)])
        guard case .object(let fallback) = disabled.structuredContent else { return XCTFail("Missing fallback") }
        XCTAssertEqual(fallback["usesFallback"], true)
        XCTAssertEqual(fallback["matchedRuleIndex"], .null)
        for url in ["file:///private/file", "https://user:secret@example.com", "javascript:alert(1)"] {
            let result = await service.call("browser_explain_route", arguments: ["url": .string(url)])
            XCTAssertEqual(result.isError, true)
        }
    }

    func testCaptureProjectionDoesNotLeakContributorIdentityWithoutOptIn() async throws {
        let start = Date(timeIntervalSince1970: 0)
        let capture = DiagnosticCapture(startedAt: start, endedAt: start.addingTimeInterval(12), samples: (0..<12).map { index in
            SystemSample(timestamp: start.addingTimeInterval(Double(index)), usedCPUCores: 3, memoryHeadroomRatio: 0.5,
                swapUsedBytes: 0, diskFreeBytes: nil, thermal: .nominal, processes: [],
                workloads: [.init(id: "process:12345:67890:private-project", name: "Private contributor · PID 12345", association: "sensitive association", cpuCores: 2, processCount: 3)])
        }, isFixture: true)
        let privateService = Diagnostics(configuration: Configuration())
        let first = await privateService.captureSummary(id: "fixture", capture: capture)
        let second = await privateService.captureSummary(id: "fixture", capture: capture)
        XCTAssertEqual(first, second)
        let text = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
        for identity in ["12345", "67890", "Private contributor", "private-project", "sensitive association"] { XCTAssertFalse(text.contains(identity)) }
        var optedIn = Configuration(); optedIn.includeProcessIdentities = true
        let disclosed = await Diagnostics(configuration: optedIn).captureSummary(id: "fixture", capture: capture)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(disclosed), as: UTF8.self).contains("Private contributor"))
    }
}
