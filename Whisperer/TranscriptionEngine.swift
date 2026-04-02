import Foundation
import SwiftWhisper

class TranscriptionEngine {
    private var whisper: Whisper?
    private(set) var isModelLoaded = false

    func loadModel(from url: URL) throws {
        whisper = Whisper(fromFileURL: url)
        isModelLoaded = true
        print("[Whisperer] Model loaded from: \(url.lastPathComponent)")
    }

    func transcribe(frames: [Float]) async throws -> String {
        guard let whisper = whisper else {
            throw WhispererError.modelNotLoaded
        }

        guard !frames.isEmpty else {
            throw WhispererError.emptyAudio
        }

        let segments = try await whisper.transcribe(audioFrames: frames)
        let text = segments
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Whisperer] Transcribed: \"\(text)\"")
        return text
    }
}
