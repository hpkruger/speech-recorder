import AppKit
import AVFoundation
import CryptoKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    struct Entry: Codable {
        let image: Data?
        let seconds: Int
    }
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("local.hanskruger.SimpleVideoRecorder/Thumbnails", isDirectory: true)
    func load(_ url: URL) async -> Entry {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let identity = "\(url.path)|\(attributes?[.size] ?? 0)|\(attributes?[.modificationDate] ?? "")"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let cacheURL = directory.appendingPathComponent(key).appendingPathExtension("json")
        if let data = try? Data(contentsOf: cacheURL), let entry = try? JSONDecoder().decode(Entry.self, from: data) { return entry }
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        guard !Task.isCancelled else { return Entry(image: nil, seconds: 0) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 100)
        let frame = try? await generator.image(at: .zero)
        let data = frame.flatMap { NSBitmapImageRep(cgImage: $0.image).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) }
        let entry = Entry(image: data, seconds: duration.isFinite ? max(0, Int(duration)) : 0)
        if data != nil, let encoded = try? JSONEncoder().encode(entry) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? encoded.write(to: cacheURL, options: .atomic)
        }
        return entry
    }
}
