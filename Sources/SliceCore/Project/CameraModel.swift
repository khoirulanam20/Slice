//
//  CameraModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import Foundation

public enum Corner: String, Codable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public enum CameraShape: String, Codable, CaseIterable {
    case landscape, portrait, square
}

public enum CameraSize: String, Codable, CaseIterable {
    case small, large
}

public enum CameraLayout: Equatable, Hashable {
    case hidden
    case corner(Corner, CameraShape, CameraSize)
    case centre(coverage: Double)
    case fullscreen
    /// `share` is the camera's fraction of the camera+screen pair along the split axis. `nil` keeps the automatic size.
    case split(SplitSide, share: Double?)

    public static let splitShareRange: ClosedRange<Double> = 0.15 ... 0.75

    public static func clampSplitShare(_ share: Double) -> Double {
        min(max(share, splitShareRange.lowerBound), splitShareRange.upperBound)
    }
}

extension CameraLayout: Codable {
    private enum Kind: String, CodingKey { case hidden, corner, centre, fullscreen, split }
    private enum EmptyKey: CodingKey {}

    private struct CornerBox: Codable {
        var _0: Corner
        var _1: CameraShape
        var _2: CameraSize
    }

    private struct CentreBox: Codable { var coverage: Double }

    private struct SplitBox: Codable {
        var side: SplitSide
        var share: Double
    }

    private struct LegacySplit: Decodable {
        var _0: SplitSide
        var share: Double?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Kind.self)
        if c.contains(.hidden) {
            self = .hidden
        } else if c.contains(.fullscreen) {
            self = .fullscreen
        } else if c.contains(.corner) {
            let box = try c.decode(CornerBox.self, forKey: .corner)
            self = .corner(box._0, box._1, box._2)
        } else if c.contains(.centre) {
            let box = try c.decode(CentreBox.self, forKey: .centre)
            self = .centre(coverage: box.coverage)
        } else if c.contains(.split) {
            self = try Self.decodeSplit(c)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing camera layout"))
        }
    }

    private static func decodeSplit(_ c: KeyedDecodingContainer<Kind>) throws -> CameraLayout {
        if let side = try? c.decode(SplitSide.self, forKey: .split) { return .split(side, share: nil) }
        if let box = try? c.decode(SplitBox.self, forKey: .split) {
            return .split(box.side, share: clampSplitShare(box.share))
        }
        let legacy = try c.decode(LegacySplit.self, forKey: .split)
        return .split(legacy._0, share: legacy.share.map(clampSplitShare))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Kind.self)
        switch self {
        case .hidden:
            _ = c.nestedContainer(keyedBy: EmptyKey.self, forKey: .hidden)
        case .fullscreen:
            _ = c.nestedContainer(keyedBy: EmptyKey.self, forKey: .fullscreen)
        case let .corner(corner, shape, size):
            try c.encode(CornerBox(_0: corner, _1: shape, _2: size), forKey: .corner)
        case let .centre(coverage):
            try c.encode(CentreBox(coverage: coverage), forKey: .centre)
        case let .split(side, share):
            if let share {
                try c.encode(SplitBox(side: side, share: Self.clampSplitShare(share)), forKey: .split)
            } else {
                try c.encode(side, forKey: .split)
            }
        }
    }
}

public enum SplitSide: String, Codable, CaseIterable {
    case left, right
}

public struct CameraBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var layout: CameraLayout

    public init(id: UUID = UUID(), start: Double, end: Double, layout: CameraLayout) {
        self.id = id
        self.start = start
        self.end = end
        self.layout = layout
    }
}
