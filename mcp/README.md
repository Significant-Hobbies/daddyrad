# DaddyRad MCP

A local, read-only stdio MCP server using the four Daddy apps' native core
libraries. Agents get bounded performance evidence, runtime-specific skill
policy, developer-storage classification and exact browser-rule precedence.

This executable runs the cores itself. It does not connect to a running app,
reuse its security bookmarks, import saved captures or verify its live settings.
The four GUI apps do not need to run. DaddyRad's website is unchanged.

## Build and connect

Source preview: `mcp-v0.1.0`. Clone the four public engine repositories listed
in [engine-revisions.json](engine-revisions.json) alongside `daddyrad` and check
out their recorded revisions before building this release. The manifest pins
the tested native sources; tracking each sibling's current main may change APIs.
For example, all five directories should share one parent folder:

```text
workspace/
  daddyrad/mcp/
  performancedaddy/
  contextdaddy/
  storagedaddy/
  browserdaddy/
```

Requires macOS 15+, Swift 6.1+ and the sibling `performancedaddy`, `contextdaddy`,
`storagedaddy` and `browserdaddy` repositories. Their library sources are linked
into one executable; sibling checkouts are needed to build, not to launch it.
The checked-in lockfile pins the official MCP Swift SDK to 0.12.1. It supplies
protocol framing, negotiation and tool dispatch rather than a custom protocol.
Existing GUI dependencies may be resolved during SwiftPM planning, but the MCP
target links only the core libraries and MCP SDK; Sparkle is not linked.

```sh
cd /Users/sarthak/Desktop/fleet/daddyrad/mcp
swift build -c release --product daddyrad-mcp
swift build -c release --show-bin-path
```

Use the resulting absolute executable path as the command in your MCP client.
For this workspace, a generic client configuration is:

```json
{
  "mcpServers": {
    "daddyrad": {
      "command": "/Users/sarthak/Desktop/fleet/daddyrad/mcp/.build/out/Products/Release/daddyrad-mcp",
      "args": []
    }
  }
}
```

No client configuration is changed by building or running the verification.
Start with `daddy_capabilities`. With no arguments only performance sampling
and supplied browser-rule evaluation are enabled. To enable folder access,
append operator-selected roots to `args`, for example:

```json
[
  "--storage-root", "/Users/sarthak/Desktop/fleet/performancedaddy",
  "--context-home", "/Users/sarthak",
  "--context-project", "/Users/sarthak/Desktop/fleet/performancedaddy"
]
```

Storage roots and context project roots are repeatable. Context home is an
explicit selection of known agent locations below that folder, not a whole-home
file-content scan. Projects require a selected context home. Use canonical
paths: broad system roots, dot components, protected paths and symlinks are
rejected (for example use `/private/tmp/...` rather than `/tmp/...`). Roots
cannot be expanded by a tool call. Names, PIDs and process project paths are
omitted unless the operator adds `--include-process-identities` at startup.

## Tools

| Tool | Evidence and use |
| --- | --- |
| `daddy_capabilities` | Selected scopes, privacy mode, engines and limits. |
| `performance_snapshot` | Native system CPU/memory/thermal and top processes; default 15, maximum 50. CPU rates may need a second sample. |
| `performance_process_history` | Resident-memory trend for a snapshot's opaque process token. Request snapshots every 10–20 seconds; gaps over 30 seconds reset continuity. |
| `performance_capture` | 3–120 seconds of native sampling with existing diagnostic and fan-investigation analysis. |
| `performance_compare` | Resource comparison for two retained capture IDs. Measurement comparability does not establish identical work or causation. |
| `context_skills` | Runtime exposure, manual/implicit policy and conflicts. Optional runtime filter and pagination, maximum 50 rows. |
| `storage_analyze` | Metadata classification and project ownership/review consequences inside a selected storage root; maximum 50 findings. |
| `browser_explain_route` | First matching rule, other matching rules, fallback and profile support for supplied `RouterConfig`. |

Example browser tool arguments (the URL is evaluated but not echoed):

```json
{
  "url": "https://docs.example.com/path",
  "config": {
    "enabled": true,
    "fallback": {"browser": "safari", "profile": ""},
    "rules": [{
      "id": "019d0000-0000-7000-8000-000000000001",
      "pattern": "*.example.com",
      "target": {"browser": "chrome", "profile": "Profile 1"}
    }]
  }
}
```

This explains the supplied rules. Installation, profile existence and current
BrowserDaddy settings remain unverified. No browser is launched.

## Bounds and privacy

- Stdout is exclusively MCP JSON; startup errors go to stderr. Closing stdin
  ends the server. No network listener or background installation is created.
- Process tokens are salted per connection and bind PID plus start time.
  History is limited to five minutes / 512 processes. Ten captures are retained
  in memory for the connection. No GUI/session identity is inferred from a
  shared agent host.
- Storage scans stop at 20,000 entries or 30 seconds and report an error when
  exceeded. DiskCore excludes symlink traversal, mounts and protected paths.
  APFS allocation totals are not guaranteed recoverable space.
- Context discovery is contained to selected roots. It may read up to 64 KiB
  per skill definition/policy file to resolve metadata; definitions, skill
  bodies, descriptions and configuration values are not returned. Symlinked
  definitions or policy paths are excluded. Policy is not proof of execution.
- Responses are limited to 128 KiB. Missing observations are unknown. Fan RPM,
  raw temperature and GPU activity are unmeasured.
- No shell, stopping processes, deletion, config writes, provider credentials,
  prompts, command arguments, environment variables, transcripts, browser
  history, tab inspection or browser automation tools are exposed.
- Returned paths/skill names are local evidence that the connected client may
  send to its model provider. Local collection does not make that client private.

## Verify

```sh
swift test --filter DiagnosticsTests
python3 scripts/verify-mcp.py .build/out/Products/Release/daddyrad-mcp
```

The protocol driver creates disposable roots and checks initialization, listing,
all eight calls, two real native captures, policy/classification/routing,
scope and linked-policy denial, scan-budget cancellation, redaction, invalid
requests and EOF shutdown.
It reports point-in-time RSS samples after requests; these are not a continuous
peak or a controlled GUI memory comparison. Tests do not use personal skill
roots, browser stores or user files.

Tracked in [DaddyRad issue #7](https://github.com/Significant-Hobbies/daddyrad/issues/7).
This preview distributes source and build instructions. It does not distribute
a signed/notarized executable or install an agent-client connection.
