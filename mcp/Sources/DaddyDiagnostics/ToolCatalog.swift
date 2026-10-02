import MCP

public enum ToolCatalog {
    private static func schema(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
        .object(["type": "object", "properties": .object(properties), "required": .array(required.map(Value.string)), "additionalProperties": false])
    }
    private static func string(_ description: String) -> Value { .object(["type": "string", "description": .string(description)]) }
    private static func integer(_ minimum: Int, _ maximum: Int, _ fallback: Int) -> Value {
        .object(["type": "integer", "minimum": .int(minimum), "maximum": .int(maximum), "default": .int(fallback)])
    }
    private static func tool(_ name: String, _ description: String, _ input: Value) -> Tool {
        Tool(name: name, description: description, inputSchema: input,
             annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false))
    }
    public static let tools: [Tool] = [
        tool("daddy_capabilities", "Inspect this connection's selected scopes, disclosure mode, limits and four native engines. No app installation or running UI is implied.", schema()),
        tool("performance_snapshot", "Read native CPU, memory, thermal and top process evidence. Opaque process tokens persist only in this server session. Names/PIDs require operator opt-in. First CPU rate can be unavailable.", schema(["limit": integer(1, 50, 15)])),
        tool("performance_process_history", "Read up to five minutes of resident-memory trend collected by this server. Gaps and PID reuse break continuity; growth is not proof of a leak. Call snapshots over time first.", schema(["process_token": string("Opaque token returned by performance_snapshot")], required: ["process_token"])),
        tool("performance_capture", "Record 3–120 seconds of native CPU/memory/thermal/workload evidence. Returns a capture ID and existing diagnostic/fan analysis. No processes are changed; fan RPM/GPU are unmeasured.", schema(["seconds": integer(3, 120, 15)])),
        tool("performance_compare", "Compare two retained captures. Reports resource changes and missing evidence. Comparable readings do not prove identical work or that a code change caused improvement.", schema(["before_id": string("Earlier capture ID"), "after_id": string("Later capture ID")], required: ["before_id", "after_id"])),
        tool("context_skills", "Resolve runtime-specific skill exposure and conflicts using ContextCore in operator-selected context roots. Does not return skill bodies, prompts or configuration values; policy is not proof of runtime execution.", schema(["runtime": string("Optional Codex, Claude, Cursor, Devin or Grok"), "offset": integer(0, 5000, 0), "limit": integer(1, 50, 20)])),
        tool("storage_analyze", "Scan metadata within an operator-selected storage root using DiskCore. Classify developer artifacts and project ownership with review consequences. No file bodies, deletion or reclaimable-byte promises. Bounded to 20,000 entries/30 seconds; exceeding a budget returns an error.", schema(["path": string("Absolute existing folder inside a --storage-root"), "limit": integer(1, 50, 20)], required: ["path"])),
        tool("browser_explain_route", "Evaluate supplied RouterConfig with BrowserCore's exact first-match rules. Reports matching-rule precedence, fallback and profile support. Supplied configuration is not verified live app state. No browser stores, history, tabs or automation are accessed.", schema(["url": string("HTTP(S) URL without credentials"), "config": .object(["type": "object", "description": "RouterConfig JSON: enabled, fallback {browser,profile}, rules [{id UUID,pattern,target {browser,profile}}], profiles. Omitted config uses BrowserCore defaults."])], required: ["url"])),
    ]
}
