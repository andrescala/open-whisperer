import Foundation

class ModelManager: NSObject, URLSessionDownloadDelegate {
    static let modelFileName = "ggml-base.en.bin"
    static let modelDownloadURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true"
    )!

    private var downloadCompletion: ((Result<URL, Error>) -> Void)?
    private var progressHandler: ((Double) -> Void)?

    func modelDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Whisperer/Models")
    }

    func localModelURL() -> URL {
        modelDirectory().appendingPathComponent(Self.modelFileName)
    }

    func isModelDownloaded() -> Bool {
        FileManager.default.fileExists(atPath: localModelURL().path)
    }

    func ensureModel(progress: @escaping (Double) -> Void) async throws -> URL {
        if isModelDownloaded() {
            return localModelURL()
        }

        try FileManager.default.createDirectory(
            at: modelDirectory(),
            withIntermediateDirectories: true
        )

        return try await downloadModel(progress: progress)
    }

    private func downloadModel(progress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.downloadCompletion = { result in
                continuation.resume(with: result)
            }
            self.progressHandler = progress

            let session = URLSession(
                configuration: .default,
                delegate: self,
                delegateQueue: .main
            )
            let task = session.downloadTask(with: Self.modelDownloadURL)
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let destination = localModelURL()
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            downloadCompletion?(.success(destination))
        } catch {
            downloadCompletion?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            downloadCompletion?(.failure(error))
        }
    }
}
