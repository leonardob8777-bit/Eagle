import Foundation
import Combine
import ImageIO

@MainActor
final class EagleRemoteMediaLoader: ObservableObject {
    enum State {
        case loading
        case loaded(Data, String, UUID)
        case failed
    }

    private static let cache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    @Published private(set) var state: State = .loading
    private var loadedURL: URL?
    private var generation = UUID()

    func release() {
        generation = UUID()
        loadedURL = nil
        state = .loading
    }

    static func clearCache() { cache.removeAllObjects() }

    func load(_ url: URL, forceRefresh: Bool = false) async {
        if !forceRefresh, loadedURL == url, case .loaded = state {
            return
        }

        loadedURL = url
        let requestGeneration = UUID()
        generation = requestGeneration
        state = .loading

        if !forceRefresh, let cached = Self.cache.object(forKey: url as NSURL) {
            state = .loaded(
                cached as Data,
                Self.mimeType(for: url, response: nil),
                requestGeneration
            )
            return
        }

        for attempt in 0..<2 {
            do {
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                var request = URLRequest(url: url)
                request.timeoutInterval = 35
                request.cachePolicy = forceRefresh || attempt > 0
                    ? .reloadIgnoringLocalCacheData
                    : .returnCacheDataElseLoad

                let (file, response) = try await URLSession.shared.download(for: request)
                defer { try? FileManager.default.removeItem(at: file) }
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }

                guard
                    let http = response as? HTTPURLResponse,
                    (200..<300).contains(http.statusCode),
                    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                    size > 0, size <= 40 * 1024 * 1024
                else {
                    throw URLError(.cannotDecodeContentData)
                }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceGetCount(source) > 0 else {
                    throw URLError(.cannotDecodeContentData)
                }

                Self.cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
                guard generation == requestGeneration else { return }
                state = .loaded(
                    data,
                    Self.mimeType(for: url, response: response),
                    requestGeneration
                )
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                }
            }
        }

        guard !Task.isCancelled, generation == requestGeneration else { return }
        state = .failed
    }

    private static func mimeType(for url: URL, response: URLResponse?) -> String {
        if let mimeType = response?.mimeType, mimeType.hasPrefix("image/") {
            return mimeType
        }

        switch url.pathExtension.lowercased() {
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "png": return "image/png"
        default: return "image/jpeg"
        }
    }
}
