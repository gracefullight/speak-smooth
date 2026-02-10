import Testing
import Foundation
@testable import SpeakSmooth

@Suite("SegmentBuilder Tests")
struct SegmentBuilderTests {
    @Test("Converts PCM Data to Float array")
    func pcmDataToFloats() {
        let floats: [Float] = [0.1, 0.5, -0.3, 0.0]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let result = SegmentBuilder.convertPCMDataToFloats(data)
        #expect(result.count == 4)
        #expect(abs(result[0] - 0.1) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)
    }

    @Test("Calculates VAD frame count from seconds")
    func frameCountFromSeconds() {
        let frames = SegmentBuilder.vadFrameCount(forSeconds: 3.0)
        #expect(frames == 94)
    }
}
