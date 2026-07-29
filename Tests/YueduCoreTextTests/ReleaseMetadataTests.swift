import Foundation
import Testing
import YueduCoreText

@Suite("YueduCoreText 0.2.0 release metadata")
struct ReleaseMetadataTests {
    @Test(
        "Documented test commands use the generated package scheme",
        arguments: [
            ".github/workflows/ci.yml",
            "README.md",
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
            schemeTokens.allSatisfy { $0 == "YueduCoreText-Package" },
            "Unexpected xcodebuild scheme in \(relativePath): \(schemeTokens)"
        )
    }

    @Test(
        "Documented simulator commands use the Xcode 16 compatible device",
        arguments: [
            ".github/workflows/ci.yml",
            "README.md",
            "CONTRIBUTING.md",
        ]
    )
    func testCommandsUseCompatibleSimulator(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)
        let simulatorNames = try matches(
            for: #"platform=iOS Simulator,name=([^'"\n\\]+)"#,
            in: contents,
            captureGroup: 1
        )

        #expect(!simulatorNames.isEmpty, "No simulator destination found in \(relativePath)")
        #expect(
            simulatorNames.allSatisfy { $0 == "iPhone 16 Pro" },
            "Incompatible simulator destination in \(relativePath): \(simulatorNames)"
        )
        #expect(!contents.contains("iPhone 17 Pro Max"))
    }

    @Test(
        "Contributor documentation retains the Xcode 16 requirement",
        arguments: ["README.md", "CONTRIBUTING.md"]
    )
    func documentationRetainsXcode16Requirement(relativePath: String) throws {
        #expect(try contentsOfFile(relativePath).contains("Xcode 16 or later"))
    }

    @Test(
        "README and changelog document every 0.2.0 public API area",
        arguments: ["README.md", "CHANGELOG.md"]
    )
    func releaseDocumentsDescribePublicAPIAreas(relativePath: String) throws {
        let contents = try contentsOfFile(relativePath)

        #expect(contents.contains("0.2.0"))
        #expect(contents.contains("ReaderContentMetrics"))
        #expect(contents.contains("TextSelectionManager"))
        #expect(contents.contains("ReaderPerfTrace"))
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
        #expect(contents.contains("out of scope"))
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
