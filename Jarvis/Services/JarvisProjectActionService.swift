import Foundation

enum JarvisProjectTemplate: String, Codable, Equatable {
    case swiftPackage = "swift-package"
    case viteReact = "vite-react"

    init(rawTemplate: String) {
        switch rawTemplate.lowercased() {
        case "react", "vite", "vite-react":
            self = .viteReact
        default:
            self = .swiftPackage
        }
    }
}

struct JarvisProjectActionResult: Codable, Equatable {
    let success: Bool
    let message: String
    let rootPath: String
    let createdPaths: [String]
}

final class JarvisProjectActionService {
    private let fileManager: FileManager
    private let actionService: JarvisMacActionService

    init(
        fileManager: FileManager = .default,
        actionService: JarvisMacActionService = JarvisMacActionService()
    ) {
        self.fileManager = fileManager
        self.actionService = actionService
    }

    func openProject(at path: String) -> JarvisProjectActionResult {
        let result = actionService.openPath(path)
        return JarvisProjectActionResult(
            success: result.succeeded,
            message: result.message,
            rootPath: result.target,
            createdPaths: []
        )
    }

    func scaffoldProject(
        at path: String,
        template: JarvisProjectTemplate,
        policy: JarvisPathSafetyPolicy
    ) -> JarvisProjectActionResult {
        let rootURL = URL(fileURLWithPath: path).standardizedFileURL
        let writableTarget = rootURL.hasDirectoryPath ? rootURL.path : rootURL.deletingLastPathComponent().path
        guard policy.canWrite(path: writableTarget) else {
            return JarvisProjectActionResult(
                success: false,
                message: "Project scaffolding is only allowed inside approved workspace paths.",
                rootPath: rootURL.path,
                createdPaths: []
            )
        }

        guard !fileManager.fileExists(atPath: rootURL.path) else {
            return JarvisProjectActionResult(
                success: false,
                message: "A file or folder already exists at \(rootURL.lastPathComponent).",
                rootPath: rootURL.path,
                createdPaths: []
            )
        }

        do {
            let scaffold = try makeScaffold(at: rootURL, template: template)
            return JarvisProjectActionResult(
                success: true,
                message: "Created \(template.rawValue) scaffold at \(rootURL.lastPathComponent).",
                rootPath: rootURL.path,
                createdPaths: scaffold
            )
        } catch {
            return JarvisProjectActionResult(
                success: false,
                message: "Failed to scaffold project: \(error.localizedDescription)",
                rootPath: rootURL.path,
                createdPaths: []
            )
        }
    }

    private func makeScaffold(at rootURL: URL, template: JarvisProjectTemplate) throws -> [String] {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var created = [rootURL.path]

        switch template {
        case .swiftPackage:
            created += try writeSwiftPackageScaffold(at: rootURL)
        case .viteReact:
            created += try writeViteReactScaffold(at: rootURL)
        }

        return created
    }

    private func writeSwiftPackageScaffold(at rootURL: URL) throws -> [String] {
        let moduleName = sanitizeModuleName(rootURL.lastPathComponent)
        let sources = rootURL.appendingPathComponent("Sources/\(moduleName)", isDirectory: true)
        let tests = rootURL.appendingPathComponent("Tests/\(moduleName)Tests", isDirectory: true)
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tests, withIntermediateDirectories: true)

        let packageSwift = """
        // swift-tools-version: 5.10
        import PackageDescription

        let package = Package(
            name: "\(moduleName)",
            platforms: [.macOS(.v14)],
            products: [
                .executable(name: "\(moduleName)", targets: ["\(moduleName)"])
            ],
            targets: [
                .executableTarget(name: "\(moduleName)"),
                .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)"])
            ]
        )
        """
        let mainSwift = """
        import Foundation

        @main
        struct \(moduleName)App {
            static func main() {
                print("Hello from \(moduleName)")
            }
        }
        """
        let testSwift = """
        import XCTest
        @testable import \(moduleName)

        final class \(moduleName)Tests: XCTestCase {
            func testExample() {
                XCTAssertTrue(true)
            }
        }
        """
        let readme = "# \(moduleName)\n\nMinimal Swift package scaffold created by Jarvis.\n"

        return try writeFiles([
            rootURL.appendingPathComponent("Package.swift"): packageSwift,
            sources.appendingPathComponent("main.swift"): mainSwift,
            tests.appendingPathComponent("\(moduleName)Tests.swift"): testSwift,
            rootURL.appendingPathComponent("README.md"): readme
        ])
    }

    private func writeViteReactScaffold(at rootURL: URL) throws -> [String] {
        let src = rootURL.appendingPathComponent("src", isDirectory: true)
        let publicDir = rootURL.appendingPathComponent("public", isDirectory: true)
        try fileManager.createDirectory(at: src, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: publicDir, withIntermediateDirectories: true)

        let packageJSON = """
        {
          "name": "\(rootURL.lastPathComponent)",
          "private": true,
          "version": "0.0.0",
          "type": "module",
          "scripts": {
            "dev": "vite",
            "build": "vite build",
            "preview": "vite preview"
          },
          "dependencies": {
            "react": "^18.3.1",
            "react-dom": "^18.3.1"
          },
          "devDependencies": {
            "@vitejs/plugin-react": "^4.3.1",
            "vite": "^5.4.0"
          }
        }
        """
        let appJSX = """
        export default function App() {
          return (
            <main>
              <h1>\(rootURL.lastPathComponent)</h1>
              <p>Minimal Vite + React scaffold created by Jarvis.</p>
            </main>
          );
        }
        """
        let mainJSX = """
        import React from "react";
        import ReactDOM from "react-dom/client";
        import App from "./App";

        ReactDOM.createRoot(document.getElementById("root")).render(
          <React.StrictMode>
            <App />
          </React.StrictMode>
        );
        """
        let viteConfig = """
        import { defineConfig } from "vite";
        import react from "@vitejs/plugin-react";

        export default defineConfig({
          plugins: [react()]
        });
        """
        let indexHTML = """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <title>\(rootURL.lastPathComponent)</title>
          </head>
          <body>
            <div id="root"></div>
            <script type="module" src="/src/main.jsx"></script>
          </body>
        </html>
        """
        let gitIgnore = "node_modules\ndist\n.DS_Store\n"

        return try writeFiles([
            rootURL.appendingPathComponent("package.json"): packageJSON,
            src.appendingPathComponent("App.jsx"): appJSX,
            src.appendingPathComponent("main.jsx"): mainJSX,
            rootURL.appendingPathComponent("vite.config.js"): viteConfig,
            rootURL.appendingPathComponent("index.html"): indexHTML,
            rootURL.appendingPathComponent(".gitignore"): gitIgnore
        ])
    }

    private func writeFiles(_ files: [URL: String]) throws -> [String] {
        var created: [String] = []
        for (url, contents) in files {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            created.append(url.path)
        }
        return created.sorted()
    }

    private func sanitizeModuleName(_ value: String) -> String {
        let filtered = value.filter { $0.isLetter || $0.isNumber }
        guard !filtered.isEmpty else { return "JarvisProject" }
        if filtered.first?.isNumber == true {
            return "Project\(filtered)"
        }
        return filtered
    }
}
