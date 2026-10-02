import Foundation

public struct DiagnosticError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Configuration: Sendable {
    public var storageRoots: [URL] = []
    public var contextHome: URL?
    public var contextProjects: [URL] = []
    public var includeProcessIdentities = false
    public init() {}

    public static func parse(_ arguments: [String]) throws -> Self {
        var config = Self()
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            if flag == "--include-process-identities" { config.includeProcessIdentities = true; continue }
            guard ["--storage-root", "--context-home", "--context-project"].contains(flag), index < arguments.count else {
                throw DiagnosticError("Unknown or incomplete startup option. Use --help.")
            }
            let path = arguments[index]; index += 1
            let root = try PathScope.root(path)
            switch flag {
            case "--storage-root": config.storageRoots.append(root)
            case "--context-home": config.contextHome = root
            default: config.contextProjects.append(root)
            }
        }
        guard config.contextHome != nil || config.contextProjects.isEmpty else {
            throw DiagnosticError("--context-project also requires --context-home; no implicit home discovery.")
        }
        return config
    }
}

public enum PathScope {
    public static func root(_ path: String) throws -> URL {
        let url = try absoluteURL(path)
        guard url.path != "/", url.path != "/System", url.path != "/Library", url.path != "/Users",
              !sensitive(url.path) else { throw DiagnosticError("This root is too broad or protected.") }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw DiagnosticError("Selected root must be an existing directory.")
        }
        guard !hasSymlinkComponent(url) else { throw DiagnosticError("Select a canonical folder without symlink components.") }
        return url
    }

    public static func require(_ path: String, within roots: [URL]) throws -> URL {
        let url = try absoluteURL(path)
        guard !sensitive(url.path), roots.contains(where: { contains(url.path, root: $0.path) }),
              !hasSymlinkComponent(url) else {
            throw DiagnosticError("Path is outside startup-selected roots, protected, or contains a symlink.")
        }
        return url
    }

    public static func contains(_ path: String, root: String) -> Bool { path == root || path.hasPrefix(root + "/") }

    private static func absoluteURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw DiagnosticError("An absolute canonical path without dot components is required.")
        }
        // standardizedFileURL rewrites /private/var to the symlink /var on macOS.
        // Keep canonical spelling so every real symlink component can be rejected.
        return URL(fileURLWithPath: path)
    }

    private static func hasSymlinkComponent(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: "/")
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil { return true }
        }
        return false
    }

    private static func sensitive(_ path: String) -> Bool {
        path.split(separator: "/").contains { part in
            let name = part.lowercased()
            return [".ssh", ".aws", ".azure", ".kube", ".gnupg", "keychains", "credentials", "secrets"].contains(name)
                || name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".pem") || name.hasSuffix(".key")
        }
    }
}
