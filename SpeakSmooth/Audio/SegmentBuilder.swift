import Foundation
import RealTimeCutVADLibrary

struct AudioSegment: Sendable {
    let pcmFloats: [Float]
    let durationSeconds: Double
}

final class SegmentBuilder: NSObject, @unchecked Sendable {
    private var accumulatedPCMData = Data()
    private let pcmQueue = DispatchQueue(label: "com.speaksmooth.pcm")
    private var isAccumulating = false

    var onSegmentReady: ((AudioSegment) -> Void)?
    var onVoiceStarted: (() -> Void)?
    var onVoiceEnded: (() -> Void)?

    private let vadWrapper: VADWrapper

    init(sampleRate: SL = .SAMPLERATE_48, silenceTimeoutSeconds: Double = 3.0) {
        self.vadWrapper = VADWrapper()
        super.init()
        vadWrapper.delegate = self
        vadWrapper.setSileroModel(.v5)
        vadWrapper.setSamplerate(sampleRate)
        updateSilenceTimeout(silenceTimeoutSeconds)
    }

    func updateSilenceTimeout(_ seconds: Double) {
        let frameCount = Self.vadFrameCount(forSeconds: seconds)
        vadWrapper.setThresholdWithVadStartDetectionProbability(
            0.7,
            vadEndDetectionProbability: 0.7,
            voiceStartVadTrueRatio: 0.5,
            voiceEndVadFalseRatio: 0.95,
            voiceStartFrameCount: 10,
            voiceEndFrameCount: Int32(frameCount)
        )
    }

    func feedAudio(buffer: UnsafePointer<Float>, count: UInt) {
        vadWrapper.processAudioData(withBuffer: buffer, count: count)
    }

    static func convertPCMDataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: floatBuffer, count: data.count / MemoryLayout<Float>.size))
        }
    }

    static func vadFrameCount(forSeconds seconds: Double) -> Int {
        let frameMs = 0.032
        return Int((seconds / frameMs).rounded(.up))
    }
}

extension SegmentBuilder: VADDelegate {
    func voiceStarted() {
        pcmQueue.sync {
            accumulatedPCMData.removeAll()
            isAccumulating = true
        }
        onVoiceStarted?()
    }

    func voiceEnded(withWavData wavData: Data!) {
        var segment: AudioSegment?
        pcmQueue.sync {
            isAccumulating = false
            if !accumulatedPCMData.isEmpty {
                let floats = Self.convertPCMDataToFloats(accumulatedPCMData)
                let duration = Double(floats.count) / 16000.0
                segment = AudioSegment(pcmFloats: floats, durationSeconds: duration)
            }
            accumulatedPCMData.removeAll()
        }
        onVoiceEnded?()
        if let segment { onSegmentReady?(segment) }
    }

    func voiceDidContinue(withPCMFloat pcmFloatData: Data!) {
        guard let data = pcmFloatData else { return }
        pcmQueue.sync {
            if isAccumulating {
                accumulatedPCMData.append(data)
            }
        }
    }
}
