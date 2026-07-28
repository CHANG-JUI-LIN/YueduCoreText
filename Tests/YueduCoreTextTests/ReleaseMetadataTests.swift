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
            "docs/superpowers/plans/2026-07-28-yuedu-coretext-0.2.0.md",
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

    @Test("Release plan records Task 4 metadata files")
    func releasePlanRecordsTask4MetadataFiles() throws {
        let contents = try contentsOfFile(
            "docs/superpowers/plans/2026-07-28-yuedu-coretext-0.2.0.md"
        )

        #expect(contents.contains(".github/workflows/ci.yml"))
        #expect(contents.contains("Tests/YueduCoreTextTests/ReleaseMetadataTests.swift"))
        #expect(
            contents.contains(
                "docs/superpowers/plans/2026-07-28-yuedu-coretext-0.2.0.md"
            )
        )
    }

    @Test("Release plan records the reviewed endpoint-token selection API")
    func releasePlanRecordsEndpointTokenSelectionAPI() throws {
        let contents = try contentsOfFile(
            "docs/superpowers/plans/2026-07-28-yuedu-coretext-0.2.0.md"
        )

        #expect(contents.contains("TextSelectionEndpoint"))
        #expect(contents.contains("endpoint(for:)"))
        #expect(contents.contains("review"))
        #expect(!contents.contains("updateSelectionStart(to:"))
        #expect(!contents.contains("updateSelectionEnd(to:"))
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
