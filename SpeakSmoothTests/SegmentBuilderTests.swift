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

    @Test("Flushes pending segment on manual stop")
    func flushPendingSegment() {
        let builder = SegmentBuilder(sampleRate: .SAMPLERATE_48, silenceTimeoutSeconds: 3.0)
        let pcm: [Float] = [0.1, 0.2, 0.3, 0.4]
        let pcmData = pcm.withUnsafeBufferPointer { Data(buffer: $0) }

        var emittedSegment: AudioSegment?
        builder.onSegmentReady = { segment in
            emittedSegment = segment
        }

        builder.voiceStarted()
        builder.voiceDidContinue(withPCMFloat: pcmData)
        let emitted = builder.flushPendingSegment()

        #expect(emitted)
        #expect(emittedSegment != nil)
        #expect(emittedSegment?.pcmFloats.count == pcm.count)
    }
}
