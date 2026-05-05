import Foundation
import WhisperKit

class TranscriptionEngine {
    private var pipe: WhisperKit?
    private(set) var isModelLoaded = false

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
        guard let pipe = pipe else { throw WhispererError.modelNotLoaded }
        guard !frames.isEmpty else { throw WhispererError.emptyAudio }

        let task: DecodingTask = translate ? .translate : .transcribe
        let options = DecodingOptions(
            task: task,
            language: translate ? "en" : nil,  // nil = auto-detect source language
            usePrefillPrompt: false             // don't bias toward English
        )
        NSLog("[AC Voice] transcribe() entered: %d frames, translate=%@", frames.count, translate ? "true" : "false")
        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(audioArray: frames, decodeOptions: options)
        } catch {
            NSLog("[AC Voice] WhisperKit.transcribe threw: %@", String(describing: error))
            throw error
        }

        let text = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        NSLog("[AC Voice] Transcribed: \"%@\"", text)
        return text
    }
}
