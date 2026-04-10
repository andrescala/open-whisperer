import AVFoundation

class AudioRecorder {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var audioFrames: [Float] = []
    private let bufferQueue = DispatchQueue(label: "com.crutech.acvoice.audiobuffer")
    private(set) var isRecording = false

    /// Called on the main thread with the current RMS audio level (0.0 to 1.0)
    var onAudioLevel: ((Float) -> Void)?

    static let targetSampleRate: Double = 16000

    /// Mic permission is handled automatically by AVAudioEngine when we access inputNode.
    /// The system shows the permission dialog using NSMicrophoneUsageDescription from Info.plist.
    /// No need to call AVCaptureDevice.requestAccess which can trigger TCC crashes.

    func startRecording() throws {
        guard !isRecording else { return }

        bufferQueue.sync { audioFrames.removeAll() }

        // Create a fresh engine each time to avoid stale input node issues
        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        print("[AC Voice] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // Sanity check — if sample rate is 0, mic permission was denied silently
        guard inputFormat.sampleRate > 0 else {
            throw WhispererError.microphonePermissionDenied
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw WhispererError.audioFormatError
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw WhispererError.audioConverterError
        }

        self.converter = newConverter
        self.engine = newEngine

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.converter else { return }

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

        newEngine.prepare()
        try newEngine.start()
        isRecording = true
        print("[AC Voice] Recording started")
    }

    func stopRecording() -> [Float] {
        guard isRecording, let engine = engine else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        self.engine = nil
        self.converter = nil

        let frames = bufferQueue.sync { audioFrames }

        print("[AC Voice] Stopped recording: \(frames.count) frames (\(String(format: "%.1f", Double(frames.count) / Self.targetSampleRate))s)")

        // Discard very short recordings (< 0.5 seconds)
        let minFrames = Int(Self.targetSampleRate * 0.5)
        guard frames.count >= minFrames else {
            print("[AC Voice] Recording too short, discarding")
            return []
        }

        // Check if audio is effectively silent (all zeros = mic not working)
        let maxAmplitude = frames.map { abs($0) }.max() ?? 0
        if maxAmplitude < 0.001 {
            print("[AC Voice] WARNING: Audio appears to be silent (max amplitude: \(maxAmplitude)). Check microphone permission.")
        }

        return frames
    }
}
