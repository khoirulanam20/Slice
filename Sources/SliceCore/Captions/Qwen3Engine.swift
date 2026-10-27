//
//  Qwen3Engine.swift
//  SliceCore
//

import FluidAudio
import Foundation

/// Bahasa Indonesia, on this Mac, through the vendored Qwen3-ASR runtime.
///
/// The decoder cache holds 512 tokens, so audio is cut into 15 second pieces. Word times are the speech inside each
/// piece spread by `WordTiming` — Qwen3 returns text only. A model that reports token times would replace that.
public actor Qwen3Engine: TranscriptionEngine {
    public static let shared = Qwen3Engine()
    static let idleTime: Duration = .seconds(600)
    /// Stays under the 512-token decoder cache once the audio prompt is counted.
    static let chunkSeconds = 15.0

    private var manager: Qwen3AsrManager?
    private var loading: Task<Qwen3AsrManager, Error>?
    private var idleUnload: Task<Void, Never>?
    private var busy = 0

    public nonisolated var kind: TranscriptionEngineKind { .qwen3 }

    public var isLoaded: Bool { manager != nil }

    public func load() async throws {
        _ = try await prepared()
        scheduleIdleUnload()
    }

    public func unload() {
        idleUnload?.cancel()
        idleUnload = nil
        loading?.cancel()
        loading = nil
        manager = nil
    }

    public func transcribe(audio url: URL, locale: Locale,
                           stage: @escaping @Sendable (TranscriptionStage) -> Void) async throws -> Transcript {
        guard locale.language.languageCode?.identifier == "id" else {
            throw TranscriptionError.unsupportedLanguage(engine: .qwen3, language: locale.languageName)
        }
        guard Qwen3Model.isInstalled else { throw TranscriptionError.qwenNotInstalled }
        busy += 1
        idleUnload?.cancel()
        defer {
            busy -= 1
            scheduleIdleUnload()
        }
        if manager == nil { stage(.preparing("Loading Bahasa Indonesia…")) }
        let asr = try await prepared()
        try Task.checkCancellation()

        let samples = try AudioConverter(sampleRate: Double(Qwen3AsrConfig.sampleRate)).resampleAudioFile(url)
        let chunk = Int(Double(Qwen3AsrConfig.sampleRate) * Self.chunkSeconds)
        let speech = AudioAnalysis.speech(in: url)
        let levels = SpeechLevels(url: url)
        var words: [Word] = []
        var offset = 0
        let total = max(samples.count, 1)
        while offset < samples.count {
            try Task.checkCancellation()
            let end = min(offset + chunk, samples.count)
            let startTime = Double(offset) / Double(Qwen3AsrConfig.sampleRate)
            let endTime = Double(end) / Double(Qwen3AsrConfig.sampleRate)
            stage(.transcribing(Double(offset) / Double(total)))
            let text = try await asr.transcribe(audioSamples: Array(samples[offset ..< end]), language: Qwen3AsrConfig.Language.indonesian)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let inside = speech.filter { $0.end > startTime && $0.start < endTime }
                let lo = inside.first?.start ?? startTime
                let hi = max(inside.last?.end ?? endTime, lo + 0.05)
                let piece = WordTiming.Piece(text: text, start: lo, end: hi, confidence: nil)
                words += WordTiming.words(fromSegments: [piece], levels: levels)
            }
            offset = end
        }
        stage(.transcribing(1))
        return Transcript(locale: locale.identifier, words: words, engine: TranscriptionBackend.qwen3.rawValue)
    }

    private func prepared() async throws -> Qwen3AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task { () throws -> Qwen3AsrManager in
            ModelHub.offlineMode = true
            let asr = Qwen3AsrManager()
            try await asr.loadModels(from: Qwen3Model.directory)
            return asr
        }
        loading = task
        do {
            let asr = try await task.value
            if loading == task { manager = asr }
            loading = nil
            return asr
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        guard busy == 0, manager != nil else { return }
        idleUnload = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTime)
            guard !Task.isCancelled else { return }
            await self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        guard busy == 0 else { return }
        unload()
    }
}
