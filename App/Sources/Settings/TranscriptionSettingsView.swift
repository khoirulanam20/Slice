//
//  TranscriptionSettingsView.swift
//  Slice
//
//  Created by rit3zh CX on 10/16/26.
//

import SliceCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            TranscriptionSettingsView()
                .tabItem { Label("Transcription", systemImage: "captions.bubble") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

struct TranscriptionSettingsView: View {
    @AppStorage(TranscriptionPreferences.engineKey) private var engine: TranscriptionEngineKind = .appleSpeech
    @AppStorage(TranscriptionPreferences.localeKey) private var localeChoice = "system"
    @ObservedObject private var parakeet = ParakeetModelStore.shared
    @ObservedObject private var qwen = Qwen3ModelStore.shared
    @State private var apple: AppleSpeechEngine.Availability?
    @State private var confirmRemove = false
    @State private var confirmRemoveQwen = false

    private var locale: Locale { localeChoice == "id-ID" ? Locale(identifier: "id-ID") : .current }
    private var indonesian: Bool { locale.language.languageCode?.identifier == "id" }
    private var engines: [TranscriptionEngineKind] {
        indonesian ? [.appleSpeech, .qwen3, .parakeet] : TranscriptionEngineKind.selectable
    }

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $localeChoice) {
                    Text("Mac language (\(Locale.current.languageName))").tag("system")
                    Text("Bahasa Indonesia").tag("id-ID")
                }
                Picker("Transcribe with", selection: $engine) {
                    ForEach(engines) { kind in
                        Text(kind == .qwen3 ? "Bahasa Indonesia" : kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(indonesian
                     ? "Choose Bahasa Indonesia to use the model below. Parakeet doesn't transcribe Indonesian. Audio stays on this Mac."
                     : "Both run on this Mac, in \(locale.languageName). Your recordings are never uploaded to transcribe them.")
                    .foregroundStyle(.secondary)
            }

            Section("Apple Speech") { appleStatus }

            if indonesian {
                Section {
                    qwenRow
                    qwenProgress
                } header: {
                    Text("Bahasa Indonesia")
                } footer: {
                    Text("Parakeet and Apple's on-device transcriber don't cover Indonesian, so Slice uses a separate model that stays on this Mac. It's downloaded once, only when you ask.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                parakeetRow
                parakeetProgress
            } header: {
                Text("Parakeet AI")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parakeet runs locally after a one-time download. It doesn't use a transcription API or an account, and works offline.")
                    Text("\(ParakeetModel.credit). \(ParakeetModel.license).")
                    Link("About the model", destination: ParakeetModel.sourceURL)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: localeChoice) { apple = await AppleSpeechEngine.availability(for: locale) }
        .onAppear {
            parakeet.refresh()
            qwen.refresh()
            if indonesian, engine == .parakeet { engine = .qwen3 }
        }
        .onChange(of: localeChoice) {
            if indonesian, engine == .parakeet { engine = .qwen3 }
            if !indonesian, engine == .qwen3 { engine = .appleSpeech }
        }
        .animation(.smooth(duration: 0.25), value: parakeet.state)
        .confirmationDialog("Delete the Bahasa Indonesia model?", isPresented: $confirmRemoveQwen) {
            Button("Delete Model", role: .destructive) { qwen.remove() }
        } message: {
            Text("This frees \(Self.size(qwen.installedBytes)). Transcripts you already have are kept. Using Bahasa Indonesia again needs the \(Self.size(Qwen3Model.downloadBytes)) download.")
        }
        .confirmationDialog("Delete the Parakeet AI model?", isPresented: $confirmRemove) {
            Button("Delete Model", role: .destructive) { parakeet.remove() }
        } message: {
            Text("This frees \(Self.size(parakeet.installedBytes)). Transcripts you already have are kept. Using Parakeet AI again needs the \(Self.size(ParakeetModel.downloadBytes)) download.")
        }
    }

    @ViewBuilder private var appleStatus: some View {
        switch apple {
        case nil:
            Text("Checking…").foregroundStyle(.secondary)
        case let .available(backend, needsAssets):
            VStack(alignment: .leading, spacing: 3) {
                Text(backend == .speechAnalyzer ? "Ready, using SpeechAnalyzer" : "Ready, using on-device speech recognition")
                if needsAssets {
                    Text("macOS downloads its \(locale.languageName) speech model the first time you transcribe.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        case .needsPermission:
            VStack(alignment: .leading, spacing: 3) {
                Text("Ready, using on-device speech recognition")
                Text("macOS asks for permission the first time you transcribe.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case let .unavailable(reason):
            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private var parakeetRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ParakeetModel.displayName)
                Text(parakeetDetail).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            parakeetButton
        }
    }

    private var parakeetDetail: String {
        switch parakeet.state {
        case .notInstalled:
            let staged = parakeet.stagedBytes
            return staged > 0
                ? "Not downloaded · \(Self.size(staged)) of \(Self.size(ParakeetModel.downloadBytes)) kept from last time"
                : "Not downloaded · \(Self.size(ParakeetModel.downloadBytes)) download"
        case let .downloading(received, total): return "Downloading… \(Self.size(received)) of \(Self.size(total))"
        case .verifying: return "Checking the downloaded files…"
        case .loading: return "Loading the model…"
        case .installed: return "On this Mac · \(Self.size(parakeet.installedBytes))\(parakeet.isLoaded ? " · Loaded" : "")"
        case .failed: return parakeet.isInstalled ? "On this Mac · \(Self.size(parakeet.installedBytes))" : "Not downloaded"
        }
    }

    @ViewBuilder private var parakeetButton: some View {
        switch parakeet.state {
        case .downloading, .verifying:
            Button("Cancel") { parakeet.cancel() }
        case .loading:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Button(parakeet.stagedBytes > 0 ? "Resume Download" : "Download") { parakeet.download() }
                .buttonStyle(.borderedProminent)
        case .installed:
            Button("Delete…") { confirmRemove = true }
        case .failed:
            HStack(spacing: 8) {
                if parakeet.isInstalled { Button("Delete…") { confirmRemove = true } }
                Button("Try Again") { parakeet.retry() }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var parakeetProgress: some View {
        switch parakeet.state {
        case let .downloading(received, total):
            ProgressView(value: Double(received), total: Double(max(total, 1)))
        case .verifying:
            ProgressView().progressViewStyle(.linear)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .notInstalled, .installed, .loading:
            if engine == .parakeet, !parakeet.isInstalled {
                Text("Download the model to transcribe with Parakeet AI. Slice won't download it without asking.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !ParakeetModel.languages.contains(locale.language.languageCode?.identifier ?? "") {
                Label(indonesian
                      ? "Parakeet AI doesn't support Bahasa Indonesia. It covers 25 European languages. Indonesian uses its own model, downloaded once."
                      : "Parakeet AI doesn't support \(locale.languageName). It covers 25 European languages.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var qwenRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Qwen3Model.displayName)
                Text(qwenDetail).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            switch qwen.state {
            case .downloading, .verifying:
                Button("Cancel") { qwen.cancel() }
            case .loading:
                ProgressView().controlSize(.small)
            case .notInstalled:
                Button(qwen.stagedBytes > 0 ? "Resume Download" : "Download") { qwen.download() }
                    .buttonStyle(.borderedProminent)
            case .installed:
                Button("Delete…") { confirmRemoveQwen = true }
            case .failed:
                Button("Try Again") { qwen.download() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var qwenDetail: String {
        switch qwen.state {
        case .notInstalled:
            return qwen.stagedBytes > 0
                ? "Not downloaded · \(Self.size(qwen.stagedBytes)) of \(Self.size(Qwen3Model.downloadBytes)) kept from last time"
                : "Not downloaded · \(Self.size(Qwen3Model.downloadBytes)) download"
        case let .downloading(received, total): return "Downloading… \(Self.size(received)) of \(Self.size(total))"
        case .verifying: return "Checking the downloaded files…"
        case .loading: return "Loading the model…"
        case .installed: return "On this Mac · \(Self.size(qwen.installedBytes))"
        case let .failed(message): return message
        }
    }

    @ViewBuilder private var qwenProgress: some View {
        switch qwen.state {
        case let .downloading(received, total):
            ProgressView(value: Double(received), total: Double(max(total, 1)))
        case .verifying:
            ProgressView().progressViewStyle(.linear)
        default:
            EmptyView()
        }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
