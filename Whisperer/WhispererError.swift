import Foundation

enum WhispererError: LocalizedError {
    case modelNotLoaded
    case emptyAudio
    case audioFormatError
    case audioConverterError
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case modelDownloadFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .emptyAudio:
            return "No audio frames to transcribe"
        case .audioFormatError:
            return "Failed to create target audio format"
        case .audioConverterError:
            return "Failed to create audio converter"
        case .microphonePermissionDenied:
            return "Microphone permission was denied"
        case .accessibilityPermissionDenied:
            return "Accessibility permission was denied"
        case .modelDownloadFailed:
            return "Failed to download the Whisper model"
        }
    }
}
