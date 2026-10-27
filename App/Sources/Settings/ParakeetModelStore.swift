//
//  ParakeetModelStore.swift
//  Slice
//
//  Created by rit3zh CX on 10/16/26.
//

import SliceCore
import SwiftUI

enum TranscriptionPreferences {
    static let engineKey = "transcriptionEngine"
    static let localeKey = "transcriptionLocale"

    /// `system` follows the Mac's language. `id-ID` is Bahasa Indonesia.
    static var localeChoice: String { UserDefaults.standard.string(forKey: localeKey) ?? "system" }

    static var locale: Locale { localeChoice == "id-ID" ? Locale(identifier: "id-ID") : .current }

    /// The engine the user picked, whether or not its model is on this Mac yet.
    static var engine: TranscriptionEngineKind {
        UserDefaults.standard.string(forKey: engineKey).flatMap(TranscriptionEngineKind.init(rawValue:)) ?? .appleSpeech
    }
}

@MainActor
final class ParakeetModelStore: ObservableObject {
    static let shared = ParakeetModelStore()

    enum State: Equatable {
        case notInstalled
        case downloading(received: Int64, total: Int64)
        case verifying
        case loading
        case installed
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var isInstalled = false
    @Published private(set) var isLoaded = false
    @Published private(set) var installedBytes: Int64 = 0
    @Published private(set) var stagedBytes: Int64 = 0
    private var task: Task<Void, Never>?

    private init() {
        state = ParakeetModel.isInstalled ? .installed : .notInstalled
        refreshSizes()
    }

    var isBusy: Bool { task != nil }
    var isFailed: Bool { if case .failed = state { true } else { false } }

    /// Downloads, checks and loads the model. Only ever started by the user.
    func download() {
        guard task == nil else { return }
        state = .downloading(received: ParakeetModel.stagedBytes, total: ParakeetModel.downloadBytes)
        let throttle = ProgressThrottle()
        task = Task {
            do {
                try await ParakeetModel.install { progress in
                    if case let .downloading(received, total) = progress,
                       !throttle.shouldReport(Double(received) / Double(max(total, 1))) { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.task != nil else { return }
                        switch self.state {
                        case .downloading, .verifying: break
                        default: return
                        }
                        switch progress {
                        case let .downloading(received, total): self.state = .downloading(received: received, total: total)
                        case .verifying: self.state = .verifying
                        }
                    }
                }
                refreshSizes()
                try await loadModel()
            } catch is CancellationError {
                state = ParakeetModel.isInstalled ? .installed : .notInstalled
            } catch {
                state = .failed(error.localizedDescription)
            }
            task = nil
            refreshSizes()
        }
    }

    /// Tries again from wherever it stopped: a download resumes with the files it already has.
    func retry() {
        guard task == nil else { return }
        guard ParakeetModel.isInstalled else { return download() }
        task = Task {
            do { try await loadModel() } catch is CancellationError { state = .installed } catch {
                state = .failed("The model is downloaded but couldn't load: \(error.localizedDescription)")
            }
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    func remove() {
        task?.cancel()
        task = nil
        Task {
            await ParakeetEngine.shared.unload()
            try? ParakeetModel.remove()
            state = ParakeetModel.isInstalled ? .installed : .notInstalled
            isLoaded = false
            refreshSizes()
        }
    }

    func refresh() {
        Task { isLoaded = await ParakeetEngine.shared.isLoaded }
        refreshSizes()
    }

    private func loadModel() async throws {
        state = .loading
        try await ParakeetEngine.shared.load()
        state = .installed
        isLoaded = await ParakeetEngine.shared.isLoaded
    }

    private func refreshSizes() {
        isInstalled = ParakeetModel.isInstalled
        installedBytes = isInstalled ? ParakeetModel.installedBytes : 0
        stagedBytes = ParakeetModel.stagedBytes
    }
}

@MainActor
final class Qwen3ModelStore: ObservableObject {
    static let shared = Qwen3ModelStore()

    enum State: Equatable {
        case notInstalled
        case downloading(received: Int64, total: Int64)
        case verifying
        case loading
        case installed
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var isInstalled = false
    @Published private(set) var installedBytes: Int64 = 0
    @Published private(set) var stagedBytes: Int64 = 0
    private var task: Task<Void, Never>?

    private init() {
        state = Qwen3Model.isInstalled ? .installed : .notInstalled
        refreshSizes()
    }

    var isBusy: Bool { task != nil }

    func download() {
        guard task == nil else { return }
        state = .downloading(received: Qwen3Model.stagedBytes, total: Qwen3Model.downloadBytes)
        let throttle = ProgressThrottle()
        task = Task {
            do {
                try await Qwen3Model.install { progress in
                    if case let .downloading(received, total) = progress,
                       !throttle.shouldReport(Double(received) / Double(max(total, 1))) { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.task != nil else { return }
                        switch progress {
                        case let .downloading(received, total): self.state = .downloading(received: received, total: total)
                        case .verifying: self.state = .verifying
                        }
                    }
                }
                refreshSizes()
                state = .loading
                try await Qwen3Engine.shared.load()
                state = .installed
            } catch is CancellationError {
                state = Qwen3Model.isInstalled ? .installed : .notInstalled
            } catch {
                state = .failed(error.localizedDescription)
            }
            task = nil
            refreshSizes()
        }
    }

    func cancel() { task?.cancel() }

    func remove() {
        task?.cancel()
        task = nil
        Task {
            await Qwen3Engine.shared.unload()
            try? Qwen3Model.remove()
            state = .notInstalled
            refreshSizes()
        }
    }

    func refresh() { refreshSizes() }

    private func refreshSizes() {
        isInstalled = Qwen3Model.isInstalled
        installedBytes = isInstalled ? Qwen3Model.installedBytes : 0
        stagedBytes = Qwen3Model.stagedBytes
    }
}
