import Testing
import Foundation
import AVFoundation
@testable import SpeakSmooth

@Suite("SegmentBuilder Tests")
struct SegmentBuilderTests {
    @Test("44.1 kHz stereo audio becomes 48 kHz mono without changing duration")
    func microphoneResampling() throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let converter = try #require(AVAudioConverter(from: source, to: target))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4410))
        buffer.frameLength = 4410
        let channels = try #require(buffer.floatChannelData)
        for index in 0..<4410 {
            let value = Float(sin(Double(index) * 2 * .pi * 440 / 44_100)) * 0.5
            channels[0][index] = value
            channels[1][index] = value
        }
        let output = try #require(AudioCaptureManager.resample(buffer, using: converter))
        #expect(output.format.sampleRate == 48_000)
        #expect(output.format.channelCount == 1)
        #expect(abs(Double(output.frameLength) / 48_000 - 0.1) < 0.01)
        let values = UnsafeBufferPointer(start: try #require(output.floatChannelData?[0]), count: Int(output.frameLength))
        #expect(values.allSatisfy { $0.isFinite })
        #expect(values.contains { abs($0) > 0.1 })
    }
    @Test("Unaligned PCM and trailing bytes are handled")
    func unalignedPCM() {
        let floats: [Float] = [0.25, -0.5]
        var data = Data([0])
        data.append(floats.withUnsafeBufferPointer { Data(buffer: $0) })
        data.append(42)
        #expect(SegmentBuilder.convertPCMDataToFloats(data.dropFirst()) == floats)
        #expect(SegmentBuilder.convertPCMDataToFloats(Data()).isEmpty)
    }

    @Test("Long speech is split without losing its tail")
    func longSpeech() {
        let builder = SegmentBuilder()
        let samples = [Float](repeating: 0.1, count: 60 * 16_000 + 16_000)
        var segments: [AudioSegment] = []
        builder.onSegmentReady = { segments.append($0) }
        builder.voiceStarted()
        builder.voiceDidContinue(withPCMFloat: samples.withUnsafeBufferPointer { Data(buffer: $0) })
        #expect(segments.count == 1)
        #expect(segments.first?.durationSeconds == 60)
        #expect(builder.flushPendingSegment())
        #expect(!builder.flushPendingSegment())
        #expect(segments.count == 2)
        #expect(segments.reduce(0) { $0 + $1.pcmFloats.count } == samples.count)
    }
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
