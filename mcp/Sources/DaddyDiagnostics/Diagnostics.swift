import BrowserCore
import ContextCore
import CryptoKit
import DiskCore
import Foundation
import MCP
import PerformanceCore

public actor Diagnostics {
    private let config: Configuration
    private let salt = UUID().uuidString
    private let sampler = WorkloadSampler()
    private var processHistory = ProcessMemoryHistory()
    private var processes: [String: LiveProcess] = [:]
    private var captures: [(String, DiagnosticCapture)] = []
    private var captureInProgress = false
    private var scanInProgress = false
    private let clockOrigin = ContinuousClock.now

    public init(configuration: Configuration) { self.config = configuration }

    public func call(_ name: String, arguments: [String: Value] = [:]) async -> CallTool.Result {
        do {
            guard let tool = ToolCatalog.tools.first(where: { $0.name == name }),
                  case .object(let schema) = tool.inputSchema, case .object(let props) = schema["properties"],
                  arguments.keys.allSatisfy({ props[$0] != nil }) else { throw DiagnosticError("Unknown tool or argument.") }
            let payload: Value
            switch name {
            case "daddy_capabilities": payload = capabilities()
            case "performance_snapshot": payload = try await snapshot(limit: integer(arguments, "limit", default: 15, range: 1...50))
            case "performance_process_history": payload = try history(token: string(arguments, "process_token"))
            case "performance_capture": payload = try await capture(seconds: integer(arguments, "seconds", default: 15, range: 3...120))
            case "performance_compare": payload = try compare(before: string(arguments, "before_id"), after: string(arguments, "after_id"))
            case "context_skills": payload = try skills(arguments)
            case "storage_analyze": payload = try await storage(path: string(arguments, "path"), limit: integer(arguments, "limit", default: 20, range: 1...50))
            case "browser_explain_route": payload = try route(arguments)
            default: throw DiagnosticError("Unknown tool.")
            }
            let data = try JSONEncoder().encode(payload)
            guard data.count <= 128 * 1024 else { throw DiagnosticError("Response exceeded the 128 KiB limit; narrow the query.") }
            return .init(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)], structuredContent: Optional.some(payload), isError: false)
        } catch {
            let message = (error as? DiagnosticError)?.message ?? "Native diagnostic unavailable or cancelled. No changes were made."
            return .init(content: [.text(text: message, annotations: nil, _meta: nil)], structuredContent: Optional.some(.object(["error": .string(message)])), isError: true)
        }
    }

    private func capabilities() -> Value {
        .object(["schema": "daddyrad.diagnostics.v1", "engines": ["PerformanceCore", "ContextCore", "DiskCore", "BrowserCore"],
            "storageRoots": .array(config.storageRoots.map { .string($0.path) }),
            "contextHome": config.contextHome.map { .string($0.path) } ?? .null,
            "contextProjects": .array(config.contextProjects.map { .string($0.path) }),
            "processIdentityDisclosure": .bool(config.includeProcessIdentities), "readOnly": true,
            "limits": .object(["captureSeconds": 120, "retainedCaptures": 10, "historySeconds": 300, "scanEntries": 20000, "scanSeconds": 30, "responseBytes": 131072]),
            "privacy": "Local collection does not prevent the connected agent from sending returned evidence to its model provider. No prompts, environment variables, credentials, browser history or command arguments are returned.",
            "scope": "Core engines run in this executable. This is not a connection to the four apps' live UI, security bookmarks, cached history or provider accounts."])
    }

    private func token(_ identity: String) -> String {
        SHA256.hash(data: Data((salt + identity).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    private func token(_ identity: ProcessIdentity) -> String { token("\(identity.pid):\(identity.started)") }
    private func now() -> Value { .string(Date().ISO8601Format()) }
    private func number(_ value: Double?) -> Value { value.flatMap { $0.isFinite ? .double($0) : nil } ?? .null }
    private func bytes(_ value: UInt64?) -> Value { value.map { .double(Double($0)) } ?? .null }

    private func snapshot(limit: Int) async throws -> Value {
        let sample = await sampler.sample()
        let time = clockOrigin.duration(to: .now).components
        processHistory.observe(sample.processes, at: Double(time.seconds) + Double(time.attoseconds) / 1e18)
        processes = Dictionary(sample.processes.sorted { $0.memory > $1.memory }.prefix(512).map { (token($0.id), $0) }, uniquingKeysWith: { first, _ in first })
        let rows = sample.processes.sorted { $0.memory == $1.memory ? $0.id.pid < $1.id.pid : $0.memory > $1.memory }.prefix(limit).map { process -> Value in
            var row: [String: Value] = ["processToken": .string(token(process.id)), "agent": process.agent.map(Value.string) ?? .null,
                "cpuPercent": number(process.cpu), "residentBytes": bytes(process.memory), "physicalFootprintBytes": bytes(process.footprint)]
            if config.includeProcessIdentities { row["pid"] = .int(Int(process.id.pid)); row["name"] = .string(process.name); row["projectPath"] = .string(process.directory) }
            return .object(row)
        }
        return .object(["capturedAt": .string(sample.date.ISO8601Format()), "evidence": "measured", "systemCPUCores": number(sample.system.usedCPUCores),
            "memoryHeadroomRatio": number(sample.system.memoryHeadroomRatio), "memoryPressure": .string(sample.pressure),
            "swapAllocatedBytes": bytes(sample.system.swapUsedBytes), "swapOutBytesPerSecond": number(sample.system.memory?.swapOutBytesPerSecond),
            "thermal": .string(sample.system.thermal.rawValue), "processCount": .int(sample.processes.count),
            "unavailableProcesses": .int(sample.unavailableProcesses), "scanSeconds": number(sample.scanSeconds), "processes": .array(rows),
            "limits": "Resident pages may be shared. Footprint is a separate estimate. Allocated swap is not current paging. Tokens last only for this connection. History begins when snapshots are requested; this does not identify conversations inside a shared host."])
    }

    private func history(token: String) throws -> Value {
        guard let process = processes[token] else { throw DiagnosticError("Process token is unknown or no longer in the tracked top 512.") }
        guard let trend = processHistory.trend(for: process.id) else {
            return .object(["processToken": .string(token), "evidence": "unavailable", "reason": "At least two continuous snapshots are required. Gaps over 30 seconds reset history."])
        }
        return .object(["processToken": .string(token), "retrievedAt": now(), "evidence": "measured", "firstResidentBytes": bytes(trend.first),
            "latestResidentBytes": bytes(trend.latest), "peakResidentBytes": bytes(trend.peak), "deltaBytes": .double(Double(trend.delta)),
            "seconds": number(trend.seconds), "samples": .int(trend.samples), "substantialGrowth": .bool(trend.growing),
            "limits": "Resident-memory growth is a review cue, not a leak diagnosis. Missing observations, gaps and PID reuse break continuity."])
    }

    private func capture(seconds: Int) async throws -> Value {
        guard !captureInProgress else { throw DiagnosticError("A capture is already running on this connection.") }
        captureInProgress = true; defer { captureInProgress = false }
        let capture = try await DiagnosticRecorder().record(duration: Double(seconds))
        let id = UUID().uuidString
        captures.append((id, capture)); if captures.count > 10 { captures.removeFirst() }
        return captureSummary(id: id, capture: capture)
    }

    func captureSummary(id: String, capture: DiagnosticCapture) -> Value {
        let report = DiagnosticEngine().analyze(capture)
        let fan = FanInvestigation.analyze(capture)
        let contributors = fan.contributors.prefix(10).map { contributor -> Value in
            var row: [String: Value] = ["workloadToken": .string(token(contributor.id)), "cpuCores": number(contributor.recordedAverageCores), "samplesPresent": .int(contributor.samplesPresent)]
            if config.includeProcessIdentities { row["name"] = .string(contributor.name); row["association"] = .string(contributor.association) }
            return .object(row)
        }
        return .object(["captureID": .string(id), "startedAt": .string(capture.startedAt.ISO8601Format()), "endedAt": .string(capture.endedAt.ISO8601Format()),
            "durationSeconds": number(capture.duration), "sampleCount": .int(capture.samples.count), "evidence": capture.isFixture ? "fixture" : "measured",
            "finding": .string(String(describing: report.finding.kind)), "confidence": .string(report.finding.confidence.rawValue),
            "cpuSeries": .array(report.cpuSeries.map { number($0) }), "averageCPUCores": number(fan.averageCPUCores),
            "peakThermal": .string(fan.peakThermal.rawValue), "sustainedCPU": .bool(fan.sustainedCPU), "cpuTrend": .string(fan.cpuTrend.rawValue),
            "workloadCoverage": .string(fan.workloadCoverage), "contributors": .array(contributors),
            "limits": "Analysis uses the app's existing deterministic rules. Fan RPM, raw temperature and GPU use are unmeasured. Workload grouping uses executable metadata/parent links, not authenticated conversation identity. No cause is established."])
    }

    private func compare(before: String, after: String) throws -> Value {
        guard before != after, let first = captures.first(where: { $0.0 == before })?.1,
              let second = captures.first(where: { $0.0 == after })?.1 else { throw DiagnosticError("Select two different retained capture IDs from this connection.") }
        let result = DiagnosticEngine().compare(before: DiagnosticEngine().analyze(first), after: DiagnosticEngine().analyze(second))
        return .object(["beforeID": .string(before), "afterID": .string(after), "retrievedAt": now(), "evidence": "derived",
            "outcome": .string(result.outcome.rawValue), "detail": .string(result.detail), "cpuDeltaCores": number(result.cpuDelta),
            "memoryHeadroomDelta": number(result.memoryHeadroomDelta),
            "limits": "Duration and measurement checks do not establish identical workloads. Resource improvement does not prove a code change caused it. Fan improvement is unmeasured."])
    }

    private func skills(_ arguments: [String: Value]) throws -> Value {
        guard let home = config.contextHome else { throw DiagnosticError("Context access is disabled. Operator must select --context-home at startup.") }
        let runtime: AgentRuntime?
        if let value = arguments["runtime"] {
            guard case .string(let name) = value, let found = AgentRuntime.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else { throw DiagnosticError("Unknown agent runtime.") }
            runtime = found
        } else { runtime = nil }
        let roots = [home] + config.contextProjects
        var report = try AIContextDiscovery.discover(configuration: .init(home: home, projectRoots: config.contextProjects, allowedRoots: roots))
        report = AIContextDiscoveryReport(items: report.items.filter { item in
            let path = canonicalCoreSpelling(item.path)
            let resolved = canonicalCoreSpelling(item.resolvedPath ?? item.path)
            let policy = URL(fileURLWithPath: resolved).deletingLastPathComponent().appendingPathComponent("agents/openai.yaml").path
            return (try? PathScope.require(path, within: roots)) != nil
                && (try? PathScope.require(resolved, within: roots)) != nil
                && (try? PathScope.require(policy, within: roots)) != nil
        }, folderRankings: report.folderRankings, coverage: report.coverage, elapsed: report.elapsed)
        let catalog = SkillPolicyResolver.resolve(report: report)
        let records = catalog.records.filter { runtime == nil || $0.policy(for: runtime!)?.isExposed == true }
        let offset = try integer(arguments, "offset", default: 0, range: 0...5000)
        let limit = try integer(arguments, "limit", default: 20, range: 1...50)
        let page = records.dropFirst(offset).prefix(limit).map { record -> Value in
            .object(["name": .string(record.name), "path": .string(record.id), "conflictCount": .int(record.definitionConflictCount),
                "needsReview": .bool(record.needsReview || record.hasDefinitionConflict),
                "policies": .array(record.policies.filter { runtime == nil || $0.runtime == runtime }.map { policy in
                    .object(["runtime": .string(policy.runtime.rawValue), "mode": .string(policy.mode.rawValue), "isExposed": .bool(policy.isExposed),
                        "evidence": .string(policy.evidence.rawValue), "reason": .string(policy.reason), "invocation": .string(policy.invocation)])
                })])
        }
        return .object(["retrievedAt": now(), "evidence": report.coverage.isPartial ? "partial" : "derived", "total": .int(records.count),
            "offset": .int(offset), "nextOffset": offset + page.count < records.count ? .int(offset + page.count) : .null,
            "skills": .array(page), "coverage": .object(["partial": .bool(report.coverage.isPartial), "unreadableCount": .int(report.coverage.unreadableCount), "skippedLinks": .int(report.coverage.skippedLinks)]),
            "limits": "Policy metadata is not proof of live prompt loading or execution. Out-of-scope and symlinked exposures are excluded. Skill bodies, config values and transcript content are not returned."])
    }

    private func canonicalCoreSpelling(_ path: String) -> String {
        // ContextCore's Foundation normalization spells Apple's /private aliases
        // as /var, /tmp and /etc. Restore only these known aliases before scope checks.
        for alias in ["/var", "/tmp", "/etc"] where path == alias || path.hasPrefix(alias + "/") {
            return "/private" + path
        }
        return path
    }

    private func storage(path: String, limit: Int) async throws -> Value {
        guard !scanInProgress else { throw DiagnosticError("A storage scan is already running on this connection.") }
        let root = try PathScope.require(path, within: config.storageRoots)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw DiagnosticError("Select an existing storage directory.") }
        scanInProgress = true; defer { scanInProgress = false }
        let budget = ScanBudget()
        let worker = Task { try await DiskScanner.scan(root: root, backend: .foundation, progress: { progress in budget.observe(progress.entries) }) }
        budget.install(worker)
        let scan: ScanResult
        do {
            scan = try await withThrowingTaskGroup(of: ScanResult.self) { group in
                group.addTask { try await worker.value }
                group.addTask { try await Task.sleep(for: .seconds(30)); worker.cancel(); throw DiagnosticError("Storage scan exceeded its 30-second budget. Select a smaller folder.") }
                defer { group.cancelAll(); worker.cancel() }
                return try await group.next()!
            }
        } catch { if budget.exceeded { throw DiagnosticError("Storage scan exceeded 20,000 entries. Select a smaller folder.") }; throw error }
        let groups = DeveloperInsights.analyze(scan)
        let report = DeveloperReport.build(scan: scan, groups: groups)
        return .object(["capturedAt": .string(scan.started.ISO8601Format()), "path": .string(root.path), "evidence": scan.skipped > 0 ? "partial" : "measured",
            "elapsedSeconds": number(scan.elapsed), "entries": .int(scan.nodes.count), "fileCount": .int(scan.fileCount), "skipped": .int(scan.skipped),
            "allocatedBytes": .double(Double(scan.nodes.first?.allocatedBytes ?? 0)), "logicalBytes": .double(Double(scan.nodes.first?.logicalBytes ?? 0)),
            "categories": .array(groups.map { .object(["category": .string($0.category.rawValue), "allocatedBytes": .double(Double($0.allocatedBytes)), "logicalBytes": .double(Double($0.logicalBytes)), "fileCount": .int($0.fileCount)]) }),
            "findingsTotal": .int(report.findings.count), "findings": .array(report.findings.prefix(limit).map { finding in
                .object(["path": .string(scan.url(for: finding.id).path), "category": .string(finding.category.rawValue), "tool": .string(finding.tool),
                    "allocatedBytes": .double(Double(finding.allocatedBytes)), "evidence": .string(finding.evidence), "consequence": .string(finding.consequence), "confidence": .string(finding.confidence)])
            }), "limits": "Metadata only; no file content was read. Symlinks and mount boundaries are not traversed. Classification is a path heuristic. APFS/shared blocks mean allocated totals are not guaranteed recoverable space. Nothing is selected for deletion."])
    }

    private func route(_ arguments: [String: Value]) throws -> Value {
        let raw = try string(arguments, "url")
        guard raw.utf8.count <= 4096, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { throw DiagnosticError("Supply a bounded HTTP(S) URL without credentials.") }
        let cfg: RouterConfig
        if let value = arguments["config"] {
            let data = try JSONEncoder().encode(value)
            guard data.count <= 64 * 1024 else { throw DiagnosticError("Routing config exceeds 64 KiB.") }
            cfg = try JSONDecoder().decode(RouterConfig.self, from: data)
        } else { cfg = RouterConfig() }
        guard cfg.rules.count <= 100, cfg.rules.allSatisfy({ $0.pattern.utf8.count <= 512 && $0.target.profile.utf8.count <= 256 }),
              cfg.fallback.profile.utf8.count <= 256 else { throw DiagnosticError("Routing rules exceed count or text limits.") }
        let matching = cfg.enabled ? cfg.rules.enumerated().filter { RuleEngine.matches($0.element.pattern, url: url) } : []
        let selected = cfg.enabled ? RuleEngine.match(url, rules: cfg.rules) : nil
        let target = selected?.target ?? cfg.fallback
        return .object(["retrievedAt": now(), "evidence": "derived", "configSource": arguments["config"] == nil ? "BrowserCore defaults" : "caller supplied; not live verified",
            "routingEnabled": .bool(cfg.enabled), "matchedRuleIndex": matching.first.map { .int($0.offset) } ?? .null,
            "otherMatchingRuleIndices": .array(matching.dropFirst().map { .int($0.offset) }),
            "target": .object(["browser": .string(target.browser.rawValue), "profile": .string(target.profile)]),
            "profileSupported": .bool(BrowserOpener.supportsProfiles(target.browser)), "usesFallback": .bool(selected == nil),
            "limits": "First match wins. Browser installation, selected profile existence and live app config are unverified. No URL was opened; query strings and fragments are not returned."])
    }

    private func string(_ args: [String: Value], _ key: String) throws -> String {
        guard case .string(let value) = args[key], !value.isEmpty, value.utf8.count <= 4096 else { throw DiagnosticError("Missing or invalid string argument: \(key).") }
        return value
    }
    private func integer(_ args: [String: Value], _ key: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value = args[key] else { return fallback }
        guard case .int(let count) = value, range.contains(count) else { throw DiagnosticError("Invalid integer range for \(key).") }
        return count
    }
}

private final class ScanBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var worker: Task<ScanResult, any Error>?
    private var hitLimit = false
    var exceeded: Bool { lock.withLock { hitLimit } }
    func install(_ task: Task<ScanResult, any Error>) { lock.withLock { worker = task; if hitLimit { task.cancel() } } }
    func observe(_ entries: Int) { if entries > 20_000 { lock.withLock { hitLimit = true; worker?.cancel() } } }
}
