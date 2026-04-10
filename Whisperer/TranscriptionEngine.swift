import Foundation
import WhisperKit

class TranscriptionEngine {
    private var pipe: WhisperKit?
    private(set) var isModelLoaded = false

    /// Downloads (if needed) and loads the WhisperKit model.
    /// WhisperKit caches models at ~/Library/Caches/huggingface/
    func loadModel(modelName: String) async throws {
        let config = WhisperKitConfig(model: modelName, verbose: false, logLevel: .none)
        pipe = try await WhisperKit(config)
        isModelLoaded = true
        print("[AC Voice] WhisperKit ready with model: \(modelName)")
    }

    func transcribe(frames: [Float]) async throws -> String {
        guard let pipe = pipe else {
            throw WhispererError.modelNotLoaded
        }

        guard !frames.isEmpty else {
            throw WhispererError.emptyAudio
        }

        let results = try await pipe.transcribe(audioArray: frames)
        let text = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[AC Voice] Transcribed: \"\(text)\"")
        return text
    }
}
