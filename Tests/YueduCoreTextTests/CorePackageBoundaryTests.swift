import Foundation
import Testing
import YueduCoreText

@Suite("Core package dependency boundary")
struct CorePackageBoundaryTests {
    @Test("Import parser recognizes supported Swift import forms")
    func importParserRecognizesSwiftImportForms() {
        let fixtures: [(source: String, expectedModule: String)] = [
            ("import UIKit", "UIKit"),
            ("import\tUIKit", "UIKit"),
            ("import class UIKit.UIView", "UIKit"),
            ("@_implementationOnly import UIKit", "UIKit"),
            ("private import UIKit", "UIKit"),
            ("public import UIKit", "UIKit"),
            ("package import UIKit", "UIKit"),
            ("internal import UIKit", "UIKit"),
            ("fileprivate import UIKit", "UIKit"),
            ("import\nUIKit", "UIKit"),
            ("import /* comment\n */ UIKit", "UIKit"),
        ]

        for fixture in fixtures {
            #expect(
                SwiftImportParser.modules(in: fixture.source)
                    == Set([fixture.expectedModule])
            )
        }
    }

    @Test("Import parser ignores comments and string literals")
    func importParserIgnoresCommentsAndStrings() {
        let source = ##"""
        // import UIKit
        /* import WebKit */
        let inline = "import Firebase"
        let multiline = """
        import RealmSwift
        """
        let raw = #"import Readium"#
        import Foundation
        """##

        #expect(SwiftImportParser.modules(in: source) == Set(["Foundation"]))
    }

    @Test("Forbidden module policy rejects exact and family dependencies")
    func forbiddenModulePolicyRejectsExactAndFamilyDependencies() {
        let importedModules: Set<String> = [
            "Foundation",
            "UIKit",
            "SwiftSoup",
            "WebKit",
            "RealmSwift",
            "ReadiumShared",
            "ReadiumStreamer",
            "FirebaseCore",
            "FirebaseAnalytics",
        ]

        #expect(
            ForbiddenCoreModulePolicy.forbiddenModules(in: importedModules)
                == Set([
                    "WebKit",
                    "RealmSwift",
                    "ReadiumShared",
                    "ReadiumStreamer",
                    "FirebaseCore",
                    "FirebaseAnalytics",
                ])
        )
    }

    @Test("Testable import parser recognizes comments between declaration tokens")
    func testableImportParserRecognizesInterleavedComments() {
        let source = """
        @testable /* rationale
        for package tests */ import YueduCoreText
        """

        #expect(SwiftImportParser.containsTestableYueduCoreTextImport(in: source))
    }

    @Test("Testable import parser ignores comments and string literals")
    func testableImportParserIgnoresCommentsAndStrings() {
        let source = ##"""
        // @testable import YueduCoreText
        /* @testable import YueduCoreText */
        let inline = "@testable import YueduCoreText"
        let multiline = """
        @testable import YueduCoreText
        """
        let raw = #"@testable import YueduCoreText"#
        import YueduCoreText
        """##

        #expect(!SwiftImportParser.containsTestableYueduCoreTextImport(in: source))
    }

    @Test("Swift file enumeration includes nested test directories")
    func swiftFileEnumerationIncludesNestedDirectories() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "YueduCoreTextBoundaryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let nestedDirectory = temporaryRoot
            .appendingPathComponent("Nested/Fixtures", isDirectory: true)
        let nestedSwiftFile = nestedDirectory.appendingPathComponent("NestedTest.swift")
        let ignoredFile = temporaryRoot.appendingPathComponent("Ignored.txt")
        try FileManager.default.createDirectory(
            at: nestedDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try "import YueduCoreText".write(
            to: nestedSwiftFile,
            atomically: true,
            encoding: .utf8
        )
        try "not Swift".write(to: ignoredFile, atomically: true, encoding: .utf8)

        let files = try swiftFiles(recursivelyUnder: temporaryRoot)

        #expect(files == [nestedSwiftFile])
    }

    @Test("Engine sources stay independent from Reader, storage and network UI layers")
    func sourceImportsAndSymbols() throws {
        let packageRoot = packageRoot()
        let sourceRoot = packageRoot
            .appendingPathComponent("Sources/YueduCoreText", isDirectory: true)
        let forbiddenSymbols = [
            "AppLogger",
            "GlobalSettings",
            "BookSourceSession",
            "PublicationSession",
            "ReaderRenderSettings",
            "ReaderStyleAssetStore",
        ]
        let files = try swiftFiles(recursivelyUnder: sourceRoot)

        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let importedForbiddenModules = ForbiddenCoreModulePolicy.forbiddenModules(
                in: SwiftImportParser.modules(in: source)
            )
            #expect(
                importedForbiddenModules.isEmpty,
                "Forbidden modules \(importedForbiddenModules.sorted()) found in \(file.path)"
            )
            for symbol in forbiddenSymbols {
                #expect(
                    !source.contains(symbol),
                    "Forbidden symbol '\(symbol)' found in \(file.path)"
                )
            }
        }
    }

    @Test("Core public tests never use testable import")
    func publicTestsDoNotUseTestableImport() throws {
        let testRoot = packageRoot()
            .appendingPathComponent("Tests/YueduCoreTextTests", isDirectory: true)
        // Internal algorithm tests are explicitly allowed. The independent consumer is public-only.
        let files = try swiftFiles(recursivelyUnder: testRoot).filter { !$0.path.contains("/Engine/") }
            + swiftFiles(recursivelyUnder: packageRoot().appendingPathComponent("Examples/StandaloneConsumer"))

        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !SwiftImportParser.containsTestableYueduCoreTextImport(in: source),
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

private enum SwiftImportParser {
    static func modules(in source: String) -> Set<String> {
        let sanitizedSource = maskingCommentsAndStrings(in: source)
        let pattern = #"(?m)^[ \t]*(?:(?:@[_A-Za-z][_A-Za-z0-9]*(?:\([^\n]*\))?|public|package|internal|fileprivate|private)\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(sanitizedSource.startIndex..., in: sanitizedSource)

        return Set(expression.matches(in: sanitizedSource, range: range).compactMap { match in
            guard let moduleRange = Range(match.range(at: 1), in: sanitizedSource) else {
                return nil
            }
            return String(sanitizedSource[moduleRange])
        })
    }

    static func containsTestableYueduCoreTextImport(in source: String) -> Bool {
        let sanitizedSource = maskingCommentsAndStrings(in: source)
        let pattern = #"(?m)^[ \t]*@testable\s+import\s+YueduCoreText\b"#
        return sanitizedSource.range(
            of: pattern,
            options: .regularExpression
        ) != nil
    }

    private static func maskingCommentsAndStrings(in source: String) -> String {
        let characters = Array(source)
        var result: [Character] = []
        result.reserveCapacity(characters.count)
        var index = 0
        var inLineComment = false
        var blockCommentDepth = 0
        var stringState: (hashCount: Int, quoteCount: Int)?

        func matches(_ token: [Character], at position: Int) -> Bool {
            guard position + token.count <= characters.count else { return false }
            return Array(characters[position..<(position + token.count)]) == token
        }

        func appendMask(count: Int) {
            result.append(contentsOf: repeatElement(" ", count: count))
        }

        func stringStart(at position: Int) -> (
            hashCount: Int,
            quoteCount: Int,
            length: Int
        )? {
            var quotePosition = position
            while quotePosition < characters.count,
                  characters[quotePosition] == "#"
            {
                quotePosition += 1
            }
            guard quotePosition < characters.count,
                  characters[quotePosition] == "\""
            else {
                return nil
            }
            let quoteCount = matches(["\"", "\"", "\""], at: quotePosition) ? 3 : 1
            return (
                hashCount: quotePosition - position,
                quoteCount: quoteCount,
                length: quotePosition - position + quoteCount
            )
        }

        while index < characters.count {
            let character = characters[index]

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    result.append(character)
                } else {
                    result.append(" ")
                }
                index += 1
                continue
            }

            if blockCommentDepth > 0 {
                if matches(["/", "*"], at: index) {
                    blockCommentDepth += 1
                    appendMask(count: 2)
                    index += 2
                } else if matches(["*", "/"], at: index) {
                    blockCommentDepth -= 1
                    appendMask(count: 2)
                    index += 2
                } else {
                    result.append(character == "\n" ? "\n" : " ")
                    index += 1
                }
                continue
            }

            if let currentStringState = stringState {
                let quoteToken = Array(
                    repeating: Character("\""),
                    count: currentStringState.quoteCount
                )
                let hashToken = Array(
                    repeating: Character("#"),
                    count: currentStringState.hashCount
                )
                let closesString = matches(quoteToken, at: index)
                    && matches(hashToken, at: index + currentStringState.quoteCount)
                if closesString {
                    let closingLength = currentStringState.quoteCount
                        + currentStringState.hashCount
                    appendMask(count: closingLength)
                    index += closingLength
                    stringState = nil
                } else if currentStringState.hashCount == 0,
                          currentStringState.quoteCount == 1,
                          character == "\\",
                          index + 1 < characters.count
                {
                    appendMask(count: 2)
                    index += 2
                } else {
                    result.append(character == "\n" ? "\n" : " ")
                    index += 1
                }
                continue
            }

            if matches(["/", "/"], at: index) {
                inLineComment = true
                appendMask(count: 2)
                index += 2
            } else if matches(["/", "*"], at: index) {
                blockCommentDepth = 1
                appendMask(count: 2)
                index += 2
            } else if let start = stringStart(at: index) {
                stringState = (start.hashCount, start.quoteCount)
                appendMask(count: start.length)
                index += start.length
            } else {
                result.append(character)
                index += 1
            }
        }

        return String(result)
    }
}

private enum ForbiddenCoreModulePolicy {
    private static let exactModules: Set<String> = [
        "WebKit",
        "RealmSwift",
    ]
    private static let moduleFamilyPrefixes = [
        "Readium",
        "Firebase",
    ]

    static func forbiddenModules(in modules: Set<String>) -> Set<String> {
        Set(modules.filter { module in
            exactModules.contains(module)
                || moduleFamilyPrefixes.contains { module.hasPrefix($0) }
        })
    }
}
