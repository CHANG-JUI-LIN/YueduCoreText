import Testing
import YueduCoreText

@Suite("Reader performance tracing public API")
struct ReaderPerfTraceTests {
    @Test("Exposes stable stage raw values and matching signpost names")
    func exposesStableStageNames() {
        let expected: [(ReaderPerfStage, String)] = [
            (.chapterLoad, "chapter.load"),
            (.htmlParse, "html.parse"),
            (.cssCollect, "css.collect"),
            (.cssParse, "css.parse"),
            (.cssMatch, "css.match"),
            (.astBuild, "ast.build"),
            (.irConvert, "ir.convert"),
            (.attributedRender, "attributed.render"),
            (.imageLoad, "resource.image.load"),
            (.imageDecode, "resource.image.decode"),
            (.layoutFingerprint, "layout.fingerprint"),
            (.layoutVerticalPrepare, "layout.vertical.prepare"),
            (.layoutFramesetterCreate, "layout.framesetter.create"),
            (.layoutPageRanges, "layout.pageRanges"),
            (.layoutDisplayList, "layout.displayList"),
            (.layoutFirstPagePublish, "layout.firstPage.publish"),
            (.renderPage, "render.page"),
            (.renderChunk, "render.chunk"),
            (.renderTile, "render.tile"),
            (.cacheDocument, "cache.document"),
            (.cacheLayout, "cache.layout"),
            (.cacheRaster, "cache.raster"),
        ]

        #expect(ReaderPerfStage.allCases.map(\.rawValue) == expected.map(\.1))
        for (stage, rawValue) in expected {
            #expect(stage.rawValue == rawValue)
            #expect(String(describing: stage.signpostName) == rawValue)
        }
    }

    @Test("Formats all metadata fields in deterministic order")
    func formatsAllMetadataFieldsInDeterministicOrder() {
        let metadata = ReaderPerfMetadata(
            resourceID: "resource-1",
            spineIndex: -1,
            characterCount: Int.max,
            elementCount: Int.min,
            ruleCount: 4,
            pageCount: 5,
            chunkCount: 6,
            writingMode: "vertical",
            cacheResult: "hit",
            executor: "main",
            generation: 7
        )

        #expect(metadata.resourceID == "resource-1")
        #expect(metadata.spineIndex == -1)
        #expect(metadata.characterCount == Int.max)
        #expect(metadata.elementCount == Int.min)
        #expect(metadata.ruleCount == 4)
        #expect(metadata.pageCount == 5)
        #expect(metadata.chunkCount == 6)
        #expect(metadata.writingMode == "vertical")
        #expect(metadata.cacheResult == "hit")
        #expect(metadata.executor == "main")
        #expect(metadata.generation == 7)
        #expect(
            metadata.logDescription
                == "resource=resource-1 spine=-1 chars=\(Int.max) elements=\(Int.min) rules=4 pages=5 chunks=6 writing=vertical cache=hit executor=main generation=7"
        )
    }

    @Test("Omits nil metadata fields")
    func omitsNilMetadataFields() {
        let metadata = ReaderPerfMetadata(
            resourceID: "resource-2",
            pageCount: 12,
            executor: "background"
        )

        #expect(
            metadata.logDescription
                == "resource=resource-2 pages=12 executor=background"
        )
        #expect(ReaderPerfMetadata().logDescription.isEmpty)
    }

    @Test("Begin and end accept public intervals")
    func beginsAndEndsInterval() {
        let interval = ReaderPerfTrace.begin(.chapterLoad)

        ReaderPerfTrace.end(interval)
    }

    @Test("Synchronous span executes its body and returns its value")
    func synchronousSpanReturnsBodyValue() {
        var didExecute = false

        let result = ReaderPerfTrace.span(.renderPage) {
            didExecute = true
            return 42
        }

        #expect(didExecute)
        #expect(result == 42)
    }

    @Test("Synchronous span rethrows the same error")
    func synchronousSpanRethrowsBodyError() {
        #expect(throws: TraceTestError.expected) {
            try ReaderPerfTrace.span(.renderPage) {
                throw TraceTestError.expected
            }
        }
    }

    @Test("Asynchronous span executes its body and returns its value")
    func asynchronousSpanReturnsBodyValue() async {
        var didExecute = false

        let result = await ReaderPerfTrace.spanAsync(.renderChunk) {
            didExecute = true
            return 84
        }

        #expect(didExecute)
        #expect(result == 84)
    }

    @Test("Asynchronous span rethrows the same error")
    func asynchronousSpanRethrowsBodyError() async {
        await #expect(throws: TraceTestError.expected) {
            try await ReaderPerfTrace.spanAsync(.renderChunk) {
                throw TraceTestError.expected
            }
        }
    }
}

private enum TraceTestError: Error {
    case expected
}
