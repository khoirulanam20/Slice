//
//  Qwen3Model.swift
//  SliceCore
//

import Foundation

/// Qwen3-ASR 0.6B, the on-device model for Bahasa Indonesia. Parakeet Ultra and Apple's SpeechTranscriber don't
/// cover it. Files are pinned to one Hugging Face revision and checked before use. Nothing is downloaded unless
/// the user asks.
public enum Qwen3Model {
    public enum Failure: LocalizedError, Equatable {
        case corrupt(String)
        case diskFull(needed: Int64)

        public var errorDescription: String? {
            switch self {
            case let .corrupt(name): "\(name) didn't match the published file, so it wasn't installed. Try again."
            case let .diskFull(needed):
                "There isn't enough free space. Bahasa Indonesia needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) more."
            }
        }
    }

    public static let displayName = "Qwen3-ASR 0.6B"
    public static let repo = "FluidInference/qwen3-asr-0.6b-coreml"
    public static let revision = "c081689ec58bcf29c2ef7c474ef78a164bda672b"
    public static let sourceURL = URL(string: "https://huggingface.co/\(repo)")!

    public static let files: [ParakeetModel.File] = [
        File("qwen3_asr_audio_encoder_v2.mlmodelc/analytics/coremldata.bin", 243, .sha256("279247406b9e8e33dc1c256d4e2b5488b9a183daf9a8314172dac9e6f64b449a")),
        File("qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin", 385, .sha256("b319012fd80686a009585fc87f50d7e683bb4da8b5bd14bd506c53e54e5bfb6f")),
        File("qwen3_asr_audio_encoder_v2.mlmodelc/metadata.json", 2088, .gitBlob("61d1c8fac4cde8d4232cef55d91245778087a6fc")),
        File("qwen3_asr_audio_encoder_v2.mlmodelc/model.mil", 726_626, .gitBlob("8fccc9a0aa40b78b6c5127d09e4cf6d4cfc9bbff")),
        File("qwen3_asr_audio_encoder_v2.mlmodelc/weights/weight.bin", 372_798_784, .sha256("7173c9f195f8fed12354edb5861d041f623ca6dc057dd0f4a3cb436ef38f3141")),
        File("qwen3_asr_decoder_stateful.mlmodelc/analytics/coremldata.bin", 243, .sha256("d841f24e1025c7e8a85195697810c8ef1f83028802cd06604dccc5618a30bad5")),
        File("qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin", 2347, .sha256("27ca2172ef8a63b6fc6c5105e501de16f2e2d4f4a0ddef9dd8b37cc26d5675e3")),
        File("qwen3_asr_decoder_stateful.mlmodelc/metadata.json", 18785, .gitBlob("a32811fd79ffcea8cb0762dcc814ed1f27890d21")),
        File("qwen3_asr_decoder_stateful.mlmodelc/model.mil", 905_438, .gitBlob("54b8380e1b964027b03f9a17de1a2243ad8caf99")),
        File("qwen3_asr_decoder_stateful.mlmodelc/weights/weight.bin", 1_192_436_160, .sha256("c5db920bb9e403b433c8d8dd09ba744f5bb57f8b5dbbc4a07ed37d57e588161d")),
        File("qwen3_asr_embeddings.bin", 311_164_936, .sha256("dd1da448e68e0ee14a74f024ebfad964f39c9abcd30ac70632796c7ce76de873")),
        File("vocab.json", 2_776_833, .gitBlob("4783fe10ac3adce15ac8f358ef5462739852c569")),
    ]

    public static var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    public static var parent: URL {
        if let dir = ProcessInfo.processInfo.environment["SLICE_QWEN3_MODEL_DIR"] { return URL(fileURLWithPath: dir) }
        return ProjectBundle.migrated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                                      "Screen Recorder", to: "Slice")
            .appendingPathComponent("Transcription").appendingPathComponent("Qwen3")
    }

    public static var directory: URL { parent.appendingPathComponent("qwen3-asr") }
    static var staging: URL { parent.appendingPathComponent(".qwen3-asr.download") }
    static var manifestURL: URL { directory.appendingPathComponent("slice-manifest.json") }

    struct Manifest: Codable {
        var repo: String
        var revision: String
        var installedAt: Date
    }

    public static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.repo == repo, manifest.revision == revision else { return false }
        return files.allSatisfy { ModelDownload.size(of: directory.appendingPathComponent($0.path)) == $0.bytes }
    }

    public static var installedBytes: Int64 { ParakeetModel.bytes(in: directory) }
    public static var stagedBytes: Int64 { ParakeetModel.bytes(in: staging) }

    public static func install(progress: @escaping @Sendable (ParakeetModel.Progress) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let total = downloadBytes
        var kept: [String: Bool] = [:]
        for file in files { kept[file.path] = try ParakeetModel.verified(file, at: staging.appendingPathComponent(file.path), sizeOnly: true) }
        let needed = files.filter { kept[$0.path] != true }.reduce(Int64(0)) { $0 + $1.bytes }
        if let free = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < needed + 50_000_000 {
            throw Failure.diskFull(needed: needed + 50_000_000 - free)
        }
        var done = total - needed
        progress(.downloading(received: done, total: total))
        for file in files where kept[file.path] != true {
            let dest = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = done
            try await ModelDownload(destination: dest) { progress(.downloading(received: before + min($0, file.bytes), total: total)) }
                .run(url(for: file))
            try Task.checkCancellation()
            done += file.bytes
            progress(.downloading(received: done, total: total))
        }
        progress(.verifying)
        for file in files {
            try Task.checkCancellation()
            let url = staging.appendingPathComponent(file.path)
            guard try ParakeetModel.verified(file, at: url, sizeOnly: false) else {
                try? fm.removeItem(at: url)
                throw Failure.corrupt(file.path)
            }
        }
        let manifest = Manifest(repo: repo, revision: revision, installedAt: Date())
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("slice-manifest.json"), options: .atomic)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }

    public static func remove() throws {
        let fm = FileManager.default
        for url in [directory, staging] where fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    static func url(for file: ParakeetModel.File) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/f32/\(file.path)")!
    }

    private typealias File = ParakeetModel.File
}
