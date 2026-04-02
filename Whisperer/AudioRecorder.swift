import AVFoundation

class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFrames: [Float] = []
    private let bufferQueue = DispatchQueue(label: "com.whisperer.audiobuffer")
    private(set) var isRecording = false

    /// Called on the main thread with the current RMS audio level (0.0 to 1.0)
    var onAudioLevel: ((Float) -> Void)?

    static let targetSampleRate: Double = 16000

    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        bufferQueue.sync { audioFrames.removeAll() }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw WhispererError.audioFormatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw WhispererError.audioConverterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let ratio = Self.targetSampleRate / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var inputProvided = false
            var conversionError: NSError?
            converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                if inputProvided {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputProvided = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard conversionError == nil,
                  let channelData = convertedBuffer.floatChannelData else { return }

            let frames = Array(UnsafeBufferPointer(
                start: channelData[0],
                count: Int(convertedBuffer.frameLength)
            ))

            // Calculate RMS level for waveform visualization
            let rms = sqrt(frames.reduce(0) { $0 + $1 * $1 } / Float(max(frames.count, 1)))
            let level = min(rms * 4.0, 1.0)  // Amplify and clamp to 0-1
            DispatchQueue.main.async {
                self.onAudioLevel?(level)
            }

            self.bufferQueue.sync {
                self.audioFrames.append(contentsOf: frames)
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let frames = bufferQueue.sync { audioFrames }

        // Discard very short recordings (< 0.5 seconds)
        let minFrames = Int(Self.targetSampleRate * 0.5)
        guard frames.count >= minFrames else {
            print("[Whisperer] Recording too short (\(frames.count) frames), discarding")
            return []
        }

        return frames
    }
}
