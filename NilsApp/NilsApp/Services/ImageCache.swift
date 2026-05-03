// Services Group
import UIKit
import CryptoKit

/// A lightweight two-level image cache (memory + disk).
///
/// Design goals
/// ────────────
/// • Zero third-party dependencies — uses URLCache / FileManager / NSCache only.
/// • Thread-safe: all mutations go through a serial `DispatchQueue`; the public
///   API is nonisolated so callers on any actor can use it freely.
/// • Automatic eviction: NSCache handles memory pressure automatically;
///   disk entries older than `maxDiskAge` (default 7 days) are purged on init.
/// • Spotify CDN compatibility: we bypass URLSession's HTTP cache entirely and
///   manage freshness ourselves, so `Cache-Control: no-cache` headers are irrelevant.
///
/// Usage
/// ─────
///   let image = await ImageCache.shared.image(for: url)
///
final class ImageCache {

    // MARK: - Singleton

    static let shared = ImageCache()

    // MARK: - Configuration

    /// Maximum number of images kept in the in-process memory cache.
    private let maxMemoryCount = 200

    /// How long a disk-cached image is considered fresh. After this interval the
    /// file is deleted on the next app launch so stale artwork is eventually refreshed.
    private let maxDiskAge: TimeInterval = 60 * 60 * 24 * 7   // 7 days

    // MARK: - Storage

    private let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    private let diskQueue  = DispatchQueue(label: "com.nilsapp.imagecache.disk", qos: .utility)
    private let cacheDir: URL

    // MARK: - Init

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("NilsAppImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        purgeExpiredDiskEntries()
    }

    // MARK: - Public API

    /// Returns a cached `UIImage` for `url`, fetching and caching it if necessary.
    /// Always safe to call from any Swift concurrency context.
    func image(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        // 1. Memory hit — synchronous, no async overhead
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // 2. Disk hit — read on background queue, then promote to memory
        if let fromDisk = await loadFromDisk(key: key) {
            memoryCache.setObject(fromDisk, forKey: key as NSString)
            return fromDisk
        }

        // 3. Network fetch — use a vanilla URLSession (no HTTP cache)
        guard let image = await fetch(url: url) else { return nil }

        // Populate both levels
        memoryCache.setObject(image, forKey: key as NSString)
        saveToDisk(image: image, key: key)

        return image
    }

    /// Removes all memory and disk cache entries. Useful for a "clear cache" debug button.
    func clearAll() {
        memoryCache.removeAllObjects()
        diskQueue.async { [cacheDir] in
            try? FileManager.default.removeItem(at: cacheDir)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private helpers

    /// A short, filesystem-safe string derived from the URL.
    private func cacheKey(for url: URL) -> String {
        // SHA256 → hex gives a fixed-length, collision-free, safe filename.
        let data   = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func diskURL(for key: String) -> URL {
        cacheDir.appendingPathComponent(key + ".jpg")
    }

    private func loadFromDisk(key: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskQueue.async { [self] in
                let url = diskURL(for: key)
                guard FileManager.default.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func saveToDisk(image: UIImage, key: String) {
        diskQueue.async { [self] in
            // Compress as JPEG at 0.85 quality — good enough for thumbnail art,
            // roughly 4–8× smaller than PNG for photographic content.
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: diskURL(for: key), options: .atomic)
        }
    }

    private func fetch(url: URL) async -> UIImage? {
        // Bypass URLSession's HTTP cache so Spotify's Cache-Control headers don't
        // prevent us from keeping the image. We manage freshness ourselves via maxDiskAge.
        let config            = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session           = URLSession(configuration: config)

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = UIImage(data: data)
        else { return nil }

        return image
    }

    private func purgeExpiredDiskEntries() {
        diskQueue.async { [self] in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { return }

            let cutoff = Date().addingTimeInterval(-maxDiskAge)
            for file in files {
                if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modified = attrs.contentModificationDate,
                   modified < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
