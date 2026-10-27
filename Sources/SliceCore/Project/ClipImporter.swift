//
//  ClipImporter.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import AVFoundation
import Foundation

public enum ClipImporter {
    public struct ImportedTakes {
        public var clips: [Clip] = []
        public var cuts: [Cut] = []
        public var splits: [Split] = []
        public var speeds: [SpeedRange] = []
        public var transitions: [ClipTransition] = []
    }

    public enum Failure: LocalizedError {
        case noVideo(String)
        case missingFile(String)
        public var errorDescription: String? {
            switch self {
            case let .noVideo(name): "\(name) has no video track."
            case let .missingFile(name): "\(name) is missing from the project."
            }
        }
    }

    public static func importVideo(_ source: URL, into bundle: ProjectBundle) async throws -> Clip {
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideo(source.lastPathComponent)
        }
        let natural = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let shown = natural.applying(transform)
        let duration = try await asset.load(.duration).seconds

        let id = UUID()
        let (dir, rel) = try bundle.makeClipFolder(id: id)
        let name = "video." + (source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent(name))

        var audioRel: String?
        if try await !asset.loadTracks(withMediaType: .audio).isEmpty,
           let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
            let out = dir.appendingPathComponent("audio.m4a")
            try await export.export(to: out, as: .m4a)
            audioRel = "\(rel)/audio.m4a"
        }
        return Clip(id: id, screenFile: "\(rel)/\(name)", micFile: nil, duration: duration,
                    screenPixelSize: CGSize(width: abs(shown.width), height: abs(shown.height)), captureRect: .zero)
            .withScreenAudio(audioRel)
    }

    /// Copies another project's takes into `destination`. The source project is left as it is. Same-folder imports
    /// are ignored. Timeline blocks that belong to the source edit (camera, zoom, music) are not copied.
    public static func importProject(_ source: ProjectBundle, into destination: ProjectBundle) async throws -> ImportedTakes {
        if source.url.standardizedFileURL.path == destination.url.standardizedFileURL.path { return ImportedTakes() }
        let project = try source.load()
        var imported = ImportedTakes()
        var ids: [UUID: UUID] = [:]
        for clip in project.clips {
            let newID = UUID()
            ids[clip.id] = newID
            let (dir, rel) = try destination.makeClipFolder(id: newID)
            var copy = clip
            copy.id = newID
            copy.annotationsImported = nil
            copy.screenFile = try copyFile(clip.screenFile, from: source, folder: dir, rel: rel)
            if let file = clip.cameraFile { copy.cameraFile = try copyFile(file, from: source, folder: dir, rel: rel) }
            if let file = clip.micFile { copy.micFile = try copyFile(file, from: source, folder: dir, rel: rel) }
            if let file = clip.screenAudioFile { copy.screenAudioFile = try copyFile(file, from: source, folder: dir, rel: rel) }
            if let file = clip.cursorFile { copy.cursorFile = try copyFile(file, from: source, folder: dir, rel: rel) }
            if let file = clip.transcriptFile { copy.transcriptFile = try copyFile(file, from: source, folder: dir, rel: rel) }
            imported.clips.append(copy)
        }
        for cut in project.cuts {
            guard let id = ids[cut.clipID] else { continue }
            imported.cuts.append(Cut(clipID: id, start: cut.start, end: cut.end))
        }
        for split in project.splits {
            guard let id = ids[split.clipID] else { continue }
            imported.splits.append(Split(clipID: id, time: split.time))
        }
        for speed in project.speeds {
            guard let id = ids[speed.clipID] else { continue }
            var copy = speed
            copy.clipID = id
            imported.speeds.append(copy)
        }
        for transition in project.transitions {
            guard let id = ids[transition.clipID] else { continue }
            imported.transitions.append(ClipTransition(clipID: id, time: transition.time, kind: transition.kind,
                                                       duration: transition.duration))
        }
        return imported
    }

    private static func copyFile(_ path: String, from source: ProjectBundle, folder: URL, rel: String) throws -> String {
        let name = (path as NSString).lastPathComponent
        let src = source.file(path)
        guard FileManager.default.fileExists(atPath: src.path) else { throw Failure.missingFile(name) }
        try FileManager.default.copyItem(at: src, to: folder.appendingPathComponent(name))
        return "\(rel)/\(name)"
    }
}

extension Clip {
    public func withScreenAudio(_ file: String?) -> Clip {
        var c = self
        c.screenAudioFile = file
        return c
    }

    public func withFrameRate(_ fps: Int) -> Clip {
        var c = self
        c.frameRate = fps
        return c
    }

    public var speechAudioFile: String? { micFile ?? screenAudioFile }
}
