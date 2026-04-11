import AVFoundation
import Accelerate

class AudioRecorder {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var audioFrames: [Float] = []
    private let bufferQueue = DispatchQueue(label: "com.crutech.acvoice.audiobuffer")
    private(set) var isRecording = false

    // FFT state — 1024-point, set up once
    private let fftSize  = 1024
    private let fftLog2n: vDSP_Length = 10   // log2(1024)
    private var fftSetup: FFTSetup?
    private var fftWindow: [Float] = []
    private var fftRing:   [Float] = []      // ring buffer of recent frames

    /// 16 normalised frequency-band magnitudes (0-1), called on the main thread.
    var onFrequencyBands: (([Float]) -> Void)?

    static let targetSampleRate: Double = 16000
    static let bandCount = 16

    init() {
        fftSetup = vDSP_create_fftsetup(fftLog2n, FFTRadix(FFT_RADIX2))
        fftWindow = [Float](repeating: 0, count: fftSize)
        fftRing   = Array(repeating: 0, count: fftSize)
        vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        bufferQueue.sync {
            audioFrames.removeAll()
            fftRing = Array(repeating: 0, count: fftSize)
        }

        let newEngine  = AVAudioEngine()
        let inputNode  = newEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        print("[AC Voice] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        guard inputFormat.sampleRate > 0 else { throw WhispererError.microphonePermissionDenied }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw WhispererError.audioFormatError }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw WhispererError.audioConverterError
        }

        self.converter = newConverter
        self.engine    = newEngine

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.converter else { return }

            let ratio = Self.targetSampleRate / inputFormat.sampleRate
            let outCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCount),
                  let channelData = converted.floatChannelData else { return }

            var inputProvided = false
            var err: NSError?
            converter.convert(to: converted, error: &err) { _, status in
                if inputProvided { status.pointee = .noDataNow; return nil }
                inputProvided = true
                status.pointee = .haveData
                return buffer
            }
            guard err == nil else { return }

            let frames = Array(UnsafeBufferPointer(start: channelData[0],
                                                   count: Int(converted.frameLength)))

            // Accumulate for transcription
            self.bufferQueue.sync { self.audioFrames.append(contentsOf: frames) }

            // FFT → frequency bands
            let bands = self.computeBands(frames)
            DispatchQueue.main.async { self.onFrequencyBands?(bands) }
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
        isRecording  = false
        self.engine    = nil
        self.converter = nil

        let frames = bufferQueue.sync { audioFrames }
        let duration = Double(frames.count) / Self.targetSampleRate
        print("[AC Voice] Stopped: \(frames.count) frames (\(String(format: "%.1f", duration))s)")

        let minFrames = Int(Self.targetSampleRate * 0.5)
        guard frames.count >= minFrames else {
            print("[AC Voice] Too short, discarding"); return []
        }
        let maxAmp = frames.map { abs($0) }.max() ?? 0
        if maxAmp < 0.001 { print("[AC Voice] WARNING: silent audio") }
        return frames
    }

    // MARK: - FFT

    /// Compute 16 log-scaled frequency bands from the latest audio frames.
    private func computeBands(_ newFrames: [Float]) -> [Float] {
        guard let setup = fftSetup else { return Array(repeating: 0, count: Self.bandCount) }

        // Slide ring buffer: drop oldest, append newest
        let n = newFrames.count
        if n >= fftSize {
            fftRing = Array(newFrames.suffix(fftSize))
        } else {
            fftRing.removeFirst(min(n, fftSize))
            fftRing.append(contentsOf: newFrames)
        }

        // Window
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(fftRing, 1, fftWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // Pack into split complex
        let halfN = fftSize / 2
        var realp  = [Float](repeating: 0, count: halfN)
        var imagp  = [Float](repeating: 0, count: halfN)
        windowed.withUnsafeBytes { raw in
            var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
            raw.bindMemory(to: DSPComplex.self).baseAddress.map {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(halfN))
            }
        }

        var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
        vDSP_fft_zrip(setup, &split, 1, fftLog2n, FFTDirection(FFT_FORWARD))

        // Magnitude
        var magnitudes = [Float](repeating: 0, count: halfN)
        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfN))

        // Normalise
        var scale = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

        // Log-scale map → 16 bands (speech range: ~80 Hz – 7 kHz)
        // At 16kHz with 1024 FFT: bin width = 15.625 Hz
        // bin 5 ≈ 78 Hz,  bin 448 ≈ 7000 Hz
        let minBin = 5
        let maxBin = min(halfN - 1, 448)
        let logMin = log2(Double(minBin))
        let logMax = log2(Double(maxBin))

        var bands = [Float](repeating: 0, count: Self.bandCount)
        for i in 0..<Self.bandCount {
            let t0 = Double(i)   / Double(Self.bandCount)
            let t1 = Double(i+1) / Double(Self.bandCount)
            let b0 = Int(pow(2, logMin + t0 * (logMax - logMin)))
            let b1 = max(b0 + 1, Int(pow(2, logMin + t1 * (logMax - logMin))))
            let slice = magnitudes[b0..<min(b1, halfN)]
            bands[i] = slice.max() ?? 0
        }

        // Normalise bands to 0-1 using a soft peak
        var peak: Float = 0
        vDSP_maxv(bands, 1, &peak, vDSP_Length(Self.bandCount))
        if peak > 0.001 {
            var div = max(peak, 0.05)
            vDSP_vsdiv(bands, 1, &div, &bands, 1, vDSP_Length(Self.bandCount))
        }

        return bands
    }
}
