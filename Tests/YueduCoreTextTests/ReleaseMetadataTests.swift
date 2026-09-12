import Foundation
import Testing
import YueduCoreText

@Suite("YueduCoreText release metadata")
struct ReleaseMetadataTests {
    @Test(
        "Documented test commands use the generated package scheme",
        arguments: [
            ".github/workflows/ci.yml",
            "README.md",
            "README.zh-Hant.md",
            "README.zh-Hans.md",
            "CONTRIBUTING.md",
        ]
    )
    func testCommandsUsePackageScheme(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)
        let schemeTokens = try matches(
            for: #"-scheme[ \t]+['"]?([^'"\s\\]+)"#,
            in: contents,
            captureGroup: 1
        )

        #expect(!schemeTokens.isEmpty, "No xcodebuild scheme found in \(relativePath)")
        #expect(
            schemeTokens.allSatisfy { ["YueduCoreText-Package", "YueduCoreTextConsumer"].contains($0) },
            "Unexpected xcodebuild scheme in \(relativePath): \(schemeTokens)"
        )
    }

    @Test(
        "Documented test commands target iOS Simulator without parallel test clones",
        arguments: [
            ".github/workflows/ci.yml",
            "README.md",
            "README.zh-Hant.md",
            "README.zh-Hans.md",
            "CONTRIBUTING.md",
        ]
    )
    func testCommandsUseCompatibleSimulator(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)
        // A caller-selected installed UDID is valid, as is CI's named device.
        // Validate the platform and execution contract rather than one device name.
        #expect(contents.contains("platform=iOS Simulator,"))
        #expect(contents.contains("-destination"))
        #expect(contents.contains("-parallel-testing-enabled NO"))
        #expect(!contents.contains("platform=macOS"))
    }

    @Test(
        "Contributor documentation retains the Xcode 16 requirement",
        arguments: ["README.md", "CONTRIBUTING.md"]
    )
    func documentationRetainsXcode16Requirement(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)
        #expect(contents.range(of: #"Xcode 16(?:\+| or later)"#,
                               options: .regularExpression) != nil)
    }

    @Test(
        "README and changelog retain the existing public utility API areas",
        arguments: ["README.md", "CHANGELOG.md"]
    )
    func releaseDocumentsDescribePublicAPIAreas(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)

        #expect(contents.contains("ReaderContentMetrics"))
        #expect(contents.contains("TextSelectionManager"))
        #expect(contents.contains("ReaderPerfTrace"))
    }

    @Test("All README translations use the compiled standalone rendering examples",
          arguments: ["README.md", "README.zh-Hant.md", "README.zh-Hans.md"])
    func readmeExamplesMatchCompiledConsumer(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)
        let swiftBlocks = try matches(for: #"(?s)```swift\n(.*?)\n```"#,
                                      in: contents, captureGroup: 1)
        let examples = swiftBlocks.filter { $0.contains("@MainActor") }
        #expect(examples.count == 2)
        let source = try contentsOfFile("Examples/StandaloneConsumer/Sources/Consumer/Example.swift")
        for example in examples { #expect(source.contains(example)) }
        let consumer = try contentsOfFile("Examples/StandaloneConsumer/Package.swift")
        #expect(consumer.contains("YueduCoreTextConsumer"))
        #expect(!source.contains("@testable"))
        for file in ["README.md", "README.zh-Hant.md", "README.zh-Hans.md"] {
            #expect(contents.contains("](\(file))"))
        }
    }

    @Test("Changelog describes only the final endpoint-token selection API")
    func changelogDescribesFinalSelectionAPI() throws {
        let contents = try contentsOfFile("CHANGELOG.md")

        #expect(contents.contains("TextSelectionEndpoint"))
        #expect(!contents.contains("Replaced separate start/end"))
        #expect(!contents.contains("reviewed"))
    }

    @Test("README states explicit rendering scope exclusions")
    func readmeStatesScopeExclusions() throws {
        let contents = try contentsOfFile("README.md").lowercased()

        #expect(contents.contains("pagination"))
        #expect(contents.contains("html"))
        #expect(contents.contains("uikit"))
        #expect(contents.contains("unsupported"))
        #expect(contents.contains("tables"))
        #expect(contents.contains("flex/grid"))
        #expect(contents.contains("vertical html document layout"))
        #expect(contents.contains("epub zip/opf/spine management"))
    }

    @Test("Contribution guidance records core dependencies and trace privacy")
    func contributionGuidanceRecordsBoundaryAndPrivacy() throws {
        let contents = try contentsOfFile("CONTRIBUTING.md")

        #expect(contents.contains("core target"))
        #expect(contents.contains("Foundation"))
        #expect(contents.contains("`os`"))
        #expect(contents.contains("title"))
        #expect(contents.contains("text"))
        #expect(contents.contains("URL"))
        #expect(contents.contains("personal data"))
    }

    @Test("DocC landing page links the public API surface and contracts")
    func docCLandingPageLinksPublicAPIAndContracts() throws {
        let contents = try contentsOfFile(
            "Sources/YueduCoreText/YueduCoreText.docc/YueduCoreText.md"
        )

        #expect(contents.contains("``ReaderContentMetrics``"))
        #expect(contents.contains("``ReaderContentUnitMap``"))
        #expect(contents.contains("``TextSelectionManager``"))
        #expect(contents.contains("``ReaderPerfTrace``"))
        #expect(contents.lowercased().contains("concurrency"))
        #expect(contents.lowercased().contains("privacy"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contentsOfFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: packageRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func matches(
        for pattern: String,
        in contents: String,
        captureGroup: Int
    ) throws -> [String] {
        let regularExpression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(contents.startIndex..., in: contents)
        return regularExpression.matches(in: contents, range: range).compactMap { match in
            guard let captureRange = Range(
                match.range(at: captureGroup),
                in: contents
            ) else {
                return nil
            }
            return String(contents[captureRange])
        }
    }

}
