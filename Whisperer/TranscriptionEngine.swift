import Foundation
import WhisperKit

class TranscriptionEngine {
    private var pipe: WhisperKit?
    private(set) var isModelLoaded = false

    /// Downloads (if needed) and loads the WhisperKit model.
    func loadModel(modelName: String) async throws {
        print("[AC Voice] Loading model: \(modelName)")
        do {
            pipe = try await WhisperKit(model: modelName)
            isModelLoaded = true
            print("[AC Voice] WhisperKit ready with model: \(modelName)")
        } catch {
            print("[AC Voice] Model load error: \(error)")
            throw error
        }
    }

    func transcribe(frames: [Float], translate: Bool = false) async throws -> String {
        guard let pipe = pipe else {
            throw WhispererError.modelNotLoaded
        }

        guard !frames.isEmpty else {
            throw WhispererError.emptyAudio
        }

        let task: DecodingTask = translate ? .translate : .transcribe
        let options = DecodingOptions(task: task)
        let results = try await pipe.transcribe(audioArray: frames, decodeOptions: options)
        let text = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[AC Voice] Transcribed: \"\(text)\"")
        return text
    }
}
