import Foundation
import DaddyDiagnostics
import MCP
@main struct DaddyRadMain {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["--help"] {
                print("""
                daddyrad-mcp — local read-only stdio MCP for four native Daddy engines
                Options:
                  --storage-root ABSOLUTE_FOLDER  (repeatable, no default)
                  --context-home ABSOLUTE_FOLDER  (agent roots below this home)
                  --context-project ABSOLUTE_FOLDER (repeatable; requires context-home)
                  --include-process-identities    (names, PIDs and project paths)
                Browser routing uses supplied rules; browser history is never read.
                Returned evidence may be sent to the connected agent's model provider.
                macOS 15+, Swift 6.1+ to build. No UI applications need to be running.
                """)
                return
            }
            let diagnostics = Diagnostics(configuration: try Configuration.parse(args))
            let server = Server(name: "DaddyRad", version: "0.1.0", capabilities: .init(tools: .init()))
            await server.withMethodHandler(ListTools.self) { _ in .init(tools: ToolCatalog.tools) }
            await server.withMethodHandler(CallTool.self) { params in await diagnostics.call(params.name, arguments: params.arguments ?? [:]) }
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data(("DaddyRad MCP: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }
}
