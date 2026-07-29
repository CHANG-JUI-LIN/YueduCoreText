import Foundation

public struct ReaderContentMetrics: Equatable, Sendable {
    public let currentUnitOffset: Int
    public let totalUnitCount: Int

    public var remainingUnitCount: Int {
        max(0, totalUnitCount - currentUnitOffset)
    }
}

public struct ReaderContentUnitMap: Equatable, Sendable {
    private let chapterOffsets: [Int]

    public init?(chapterUnitCounts: [Int]) {
        guard !chapterUnitCounts.isEmpty,
              chapterUnitCounts.allSatisfy({ $0 >= 0 })
        else {
            return nil
        }

        var offsets = [0]
        offsets.reserveCapacity(chapterUnitCounts.count + 1)
        for count in chapterUnitCounts {
            let (next, overflow) = offsets[offsets.count - 1].addingReportingOverflow(count)
            guard !overflow else { return nil }
            offsets.append(next)
        }
        guard offsets[offsets.count - 1] > 0 else { return nil }
        chapterOffsets = offsets
    }

    public var totalUnitCount: Int {
        chapterOffsets[chapterOffsets.count - 1]
    }

    public func metrics(
        spineIndex: Int,
        localCharacterOffset: Int,
        currentChapterCharacterCount: Int?
    ) -> ReaderContentMetrics? {
        guard spineIndex >= 0,
              spineIndex < chapterOffsets.count - 1,
              localCharacterOffset >= 0
        else {
            return nil
        }

        let chapterStart = chapterOffsets[spineIndex]
        let chapterUnitCount = chapterOffsets[spineIndex + 1] - chapterStart
        let localUnitOffset: Int

        if localCharacterOffset == 0 || chapterUnitCount == 0 {
            localUnitOffset = 0
        } else {
            guard let currentChapterCharacterCount,
                  currentChapterCharacterCount > 0
            else {
                return nil
            }
            let clampedOffset = min(localCharacterOffset, currentChapterCharacterCount)
            if clampedOffset == currentChapterCharacterCount {
                localUnitOffset = chapterUnitCount
            } else {
                let product = clampedOffset.multipliedFullWidth(by: chapterUnitCount)
                localUnitOffset = currentChapterCharacterCount
                    .dividingFullWidth(product)
                    .quotient
            }
        }

        let (currentUnitOffset, overflow) = chapterStart.addingReportingOverflow(localUnitOffset)
        guard !overflow else { return nil }
        return ReaderContentMetrics(
            currentUnitOffset: currentUnitOffset,
            totalUnitCount: totalUnitCount
        )
    }
}
