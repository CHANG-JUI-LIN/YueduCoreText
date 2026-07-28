import Foundation
import Testing
import YueduCoreText

@Suite("Core package dependency boundary")
struct CorePackageBoundaryTests {
    @Test("Core sources stay independent from app and third-party layers")
    func sourceImportsAndSymbols() throws {
        let packageRoot = packageRoot()
        let sourceRoot = packageRoot
            .appendingPathComponent("Sources/YueduCoreText", isDirectory: true)
        let forbiddenFragments = [
            "import UIKit",
            "import Readium",
            "import SwiftSoup",
            "import WebKit",
            "import Firebase",
            "import RealmSwift",
            "AppLogger",
            "GlobalSettings",
            "BookSourceSession",
        ]
        let files = try swiftFiles(recursivelyUnder: sourceRoot)

        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for fragment in forbiddenFragments {
                #expect(
                    !source.contains(fragment),
                    "Forbidden dependency '\(fragment)' found in \(file.path)"
                )
            }
        }
    }

    @Test("Core public tests never use testable import")
    func publicTestsDoNotUseTestableImport() throws {
        let testRoot = packageRoot()
            .appendingPathComponent("Tests/YueduCoreTextTests", isDirectory: true)
        let forbiddenImportPattern = #"@testable\s+import\s+YueduCoreText\b"#
        let files = try FileManager.default.contentsOfDirectory(
            at: testRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension == "swift" }

        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                source.range(
                    of: forbiddenImportPattern,
                    options: .regularExpression
                ) == nil,
                "Public API test uses a testable import in \(file.lastPathComponent)"
            )
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(recursivelyUnder root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let file = item as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: Set(keys)).isRegularFile == true
            else {
                return nil
            }
            return file
        }
    }
}
