import Testing
import YueduCoreText

@Suite("Reader content metrics public API")
struct ReaderContentMetricsTests {
    @Test("Converts a chapter-local character offset into the global unit offset")
    func convertsLocalOffsetToGlobalUnits() throws {
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [100, 200]))

        let metrics = try #require(
            unitMap.metrics(
                spineIndex: 1,
                localCharacterOffset: 50,
                currentChapterCharacterCount: 100
            )
        )

        #expect(metrics.currentUnitOffset == 200)
        #expect(metrics.totalUnitCount == 300)
        #expect(metrics.remainingUnitCount == 100)
    }

    @Test("Rejects negative chapter unit counts")
    func rejectsNegativeUnitCounts() {
        #expect(ReaderContentUnitMap(chapterUnitCounts: [100, -1]) == nil)
    }

    @Test("Rejects an all-zero chapter unit map")
    func rejectsAllZeroUnitMap() {
        #expect(ReaderContentUnitMap(chapterUnitCounts: [0, 0]) == nil)
    }

    @Test("Rejects chapter unit totals that overflow Int")
    func rejectsOverflowingUnitTotal() {
        #expect(ReaderContentUnitMap(chapterUnitCounts: [Int.max, 1]) == nil)
    }

    @Test(
        "Rejects a spine index outside the unit map",
        arguments: [-1, 2]
    )
    func rejectsInvalidSpineIndex(spineIndex: Int) throws {
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [100, 200]))

        #expect(
            unitMap.metrics(
                spineIndex: spineIndex,
                localCharacterOffset: 0,
                currentChapterCharacterCount: 100
            ) == nil
        )
    }

    @Test("Rejects Int.max as a spine index without overflowing")
    func rejectsMaximumSpineIndex() throws {
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [100]))

        #expect(
            unitMap.metrics(
                spineIndex: Int.max,
                localCharacterOffset: 0,
                currentChapterCharacterCount: nil
            ) == nil
        )
    }

    @Test("Clamps a local character offset to the chapter end")
    func clampsLocalOffsetToChapterEnd() throws {
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [100, 200]))

        let metrics = try #require(
            unitMap.metrics(
                spineIndex: 1,
                localCharacterOffset: 150,
                currentChapterCharacterCount: 100
            )
        )

        #expect(metrics.currentUnitOffset == 300)
        #expect(metrics.remainingUnitCount == 0)
    }

    @Test("Maps an Int.max-sized chapter end without overflowing")
    func mapsMaximumUnitCountChapterEnd() throws {
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [Int.max]))

        let metrics = try #require(
            unitMap.metrics(
                spineIndex: 0,
                localCharacterOffset: 1,
                currentChapterCharacterCount: 1
            )
        )

        #expect(metrics.currentUnitOffset == Int.max)
        #expect(metrics.totalUnitCount == Int.max)
        #expect(metrics.remainingUnitCount == 0)
    }

    @Test("Rounds a large non-terminal proportional offset down")
    func roundsLargeProportionalOffsetDown() throws {
        let unitCount = (1 << 53) + 3
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [unitCount]))

        let metrics = try #require(
            unitMap.metrics(
                spineIndex: 0,
                localCharacterOffset: 1,
                currentChapterCharacterCount: 2
            )
        )

        #expect(metrics.currentUnitOffset == 4_503_599_627_370_497)
        #expect(metrics.totalUnitCount == unitCount)
    }

    @Test(
        "Rejects a positive local offset without a positive character count",
        arguments: [Int?.none, 0]
    )
    func rejectsPositiveOffsetWithoutCharacterCount(
        currentChapterCharacterCount: Int?
    ) throws {
        let unitMap = try #require(ReaderContentUnitMap(chapterUnitCounts: [100, 200]))

        #expect(
            unitMap.metrics(
                spineIndex: 1,
                localCharacterOffset: 1,
                currentChapterCharacterCount: currentChapterCharacterCount
            ) == nil
        )
    }
}
