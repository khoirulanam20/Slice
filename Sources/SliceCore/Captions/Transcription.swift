//
//  Transcription.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/16/26.
//

import Foundation

/// The speech recognisers Slice offers. All run on this Mac; none sends audio anywhere.
/// `qwen3` is the Bahasa Indonesia model. It appears in Settings when that language is chosen.
public enum TranscriptionEngineKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case appleSpeech
    case parakeet
    case qwen3

    /// Engines shown for every language. Bahasa Indonesia adds `qwen3`.
    public static let selectable: [TranscriptionEngineKind] = [.appleSpeech, .parakeet]

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .parakeet: "Parakeet AI"
        case .qwen3: "Qwen3"
        }
    }

    public var engine: any TranscriptionEngine {
        switch self {
        case .appleSpeech: AppleSpeechEngine()
        case .parakeet: ParakeetEngine.shared
        case .qwen3: Qwen3Engine.shared
        }
    }
}

/// Which recogniser runs for a language. Parakeet only when it was trained on that language. Apple when this Mac
/// can do it on device. Bahasa Indonesia falls through to Qwen3, which stays on this Mac.
public enum TranscriptionRouter {
    public static func route(engine: TranscriptionEngineKind, locale: Locale, appleOnDevice: Bool) -> TranscriptionEngineKind {
        let code = locale.language.languageCode?.identifier ?? ""
        if engine == .qwen3, code == "id" { return .qwen3 }
        if engine == .parakeet, ParakeetModel.languages.contains(code) { return .parakeet }
        if appleOnDevice { return .appleSpeech }
        if code == "id" { return .qwen3 }
        return .appleSpeech
    }
}

/// The recogniser that actually made a transcript, kept with it.
public enum TranscriptionBackend: String, Sendable {
    case speechAnalyzer = "apple-speech-analyzer"
    case speechRecognizer = "apple-speech-recognizer"
    case parakeetUltra = "parakeet-ultra"
    case qwen3 = "qwen3-asr"

    public var displayName: String {
        switch self {
        case .speechAnalyzer, .speechRecognizer: "Apple Speech"
        case .parakeetUltra: "Parakeet AI"
        case .qwen3: "Qwen3"
        }
    }
}

public enum TranscriptionStage: Equatable, Sendable {
    /// Getting ready: asking for permission, loading a model.
    case preparing(String)
    /// Apple installing its on-device language model, with the system's own progress when it gives one.
    case installingAssets(Double?)
    case transcribing(Double)
}

public protocol TranscriptionEngine: Sendable {
    var kind: TranscriptionEngineKind { get }
    func transcribe(audio url: URL, locale: Locale,
                    stage: @escaping @Sendable (TranscriptionStage) -> Void) async throws -> Transcript
}

public enum TranscriptionError: LocalizedError, Equatable {
    case unsupportedLanguage(engine: TranscriptionEngineKind, language: String)
    case onDeviceUnavailable(language: String)
    case recognizerUnavailable
    case notAuthorized
    case modelNotInstalled
    case qwenNotInstalled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedLanguage(engine, language):
            "\(engine.displayName) can't transcribe \(language). Choose the other engine in Settings › Transcription."
        case let .onDeviceUnavailable(language):
            "On-device speech recognition for \(language) isn't available on this Mac, and Slice doesn't send your audio to Apple's servers. Try Parakeet AI in Settings › Transcription."
        case .recognizerUnavailable:
            "Apple's speech recogniser isn't available right now. Try again in a moment."
        case .notAuthorized:
            "Slice isn't allowed to use speech recognition. Allow it in System Settings › Privacy & Security › Speech Recognition, or switch to Parakeet AI."
        case .modelNotInstalled:
            "The Parakeet AI model isn't on this Mac yet. Download it in Settings › Transcription, or switch to Apple Speech."
        case .qwenNotInstalled:
            "The Bahasa Indonesia model isn't on this Mac yet. Download it in Settings › Transcription."
        case let .failed(message):
            message
        }
    }
}

extension Locale {
    /// The language's name in the user's own language, e.g. "English (United Kingdom)".
    public var languageName: String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
