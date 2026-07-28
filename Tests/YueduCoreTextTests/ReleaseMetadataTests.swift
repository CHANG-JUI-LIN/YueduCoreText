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
        let missingPaths = Task4GitAddGuard.missingRequiredPaths(
            in: contents,
            requiredPaths: requiredTask4GitAddPaths
        )

        #expect(
            missingPaths.isEmpty,
            "Task 4 Step 6 git add is missing: \(missingPaths.sorted())"
        )
    }

    @Test("Task 4 git add guard rejects a path present outside the command")
    func task4GitAddGuardRejectsMissingCommandPath() {
        let completeFixture = """
        ### Task 4: Documentation

        **Files:**
        - Modify: `README.md`
        - Create: `CHANGELOG.md`

        - [ ] **Step 6: Commit**

        ```bash
        git add README.md CHANGELOG.md
        git commit -m "docs: fixture"
        ```

        ### Task 5: Audit
        """
        let mutatedFixture = completeFixture.replacingOccurrences(
            of: "git add README.md CHANGELOG.md",
            with: "git add CHANGELOG.md"
        )
        let requiredPaths: Set<String> = ["README.md", "CHANGELOG.md"]

        #expect(
            Task4GitAddGuard.missingRequiredPaths(
                in: completeFixture,
                requiredPaths: requiredPaths
            ).isEmpty
        )
        #expect(
            Task4GitAddGuard.missingRequiredPaths(
                in: mutatedFixture,
                requiredPaths: requiredPaths
            ) == Set(["README.md"])
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

    private var requiredTask4GitAddPaths: Set<String> {
        [
            ".github/workflows/ci.yml",
            "README.md",
            "CONTRIBUTING.md",
            "CHANGELOG.md",
            "Sources/YueduCoreText/YueduCoreText.docc",
            "Tests/YueduCoreTextTests/CorePackageBoundaryTests.swift",
            "Tests/YueduCoreTextTests/ReleaseMetadataTests.swift",
            "docs/superpowers/plans/2026-07-28-yuedu-coretext-0.2.0.md",
        ]
    }
}

private enum Task4GitAddGuard {
    static func missingRequiredPaths(
        in plan: String,
        requiredPaths: Set<String>
    ) -> Set<String> {
        guard let task4Section = section(
            in: plan,
            startingWith: "### Task 4:",
            endingWith: "### Task 5:"
        ),
        let step6Section = section(
            in: task4Section,
            startingWith: "- [ ] **Step 6:",
            endingWith: "- [ ] **Step 7:"
        ),
        let gitAddPaths = gitAddPaths(in: step6Section)
        else {
            return requiredPaths
        }

        return requiredPaths.subtracting(gitAddPaths)
    }

    private static func section(
        in contents: String,
        startingWith startMarker: String,
        endingWith endMarker: String
    ) -> String? {
        guard let start = contents.range(of: startMarker) else { return nil }
        let sectionStart = start.lowerBound
        let remaining = contents[start.upperBound...]
        let sectionEnd = remaining.range(of: endMarker)?.lowerBound ?? contents.endIndex
        return String(contents[sectionStart..<sectionEnd])
    }

    private static func gitAddPaths(in stepSection: String) -> Set<String>? {
        guard let fenceStart = stepSection.range(of: "```bash"),
              let fenceEnd = stepSection[fenceStart.upperBound...].range(of: "```")
        else {
            return nil
        }
        let commandBlock = stepSection[fenceStart.upperBound..<fenceEnd.lowerBound]
            .replacingOccurrences(of: "\\\n", with: " ")

        for line in commandBlock.split(separator: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.starts(with: ["git", "add"]) else { continue }
            return Set(tokens.dropFirst(2))
        }
        return nil
    }
}
