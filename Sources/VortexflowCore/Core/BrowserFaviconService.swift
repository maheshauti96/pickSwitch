import CoreGraphics
import Foundation
import ImageIO

/// Resolves a browser window's active site icon without touching browser profile data or a
/// third-party favicon service.
///
/// The conventional `/favicon.ico` is tried first. When modern sites declare a different icon,
/// only the origin root (`https://host/`) is read — never the active tab's full path — and only
/// same-origin HTTPS icon declarations are accepted. The session is ephemeral and has no cookies,
/// credentials or URL cache; redirects cannot leave that exact origin. A bounded, decoded raster
/// image is cached in process memory, never the untrusted source container or HTML.
actor BrowserFaviconService {

    private static let maximumResponseBytes = 1_048_576
    private static let maximumHTMLBytes = 512 * 1_024
    private static let maximumIconCandidates = 6
    private static let maximumSourceDimension = 1_024
    private static let maximumSourcePixelCount = 1_048_576
    private static let maximumSourceRepresentations = 32
    private static let renderedDimension = 256
    private static let maximumCacheEntries = 128
    private static let maximumCacheBytes = 8 * 1_048_576
    private static let maximumFailureCacheEntries = 256
    private static let maximumPendingDownloads = 32
    private static let maximumPrefetchDownloads = 4
    private static let failureCacheDuration: TimeInterval = 5 * 60
    private static let downloadGate = DownloadGate(limit: maximumPrefetchDownloads)

    private struct CachedImage {
        let image: CGImage
        let cost: Int
    }

    private struct DownloadedResource {
        let data: Data
        let response: HTTPURLResponse
    }

    private struct IconCandidate {
        let url: URL
        let score: Int
        let order: Int
    }

    private var cache: [WebOrigin: CachedImage] = [:]
    private var cacheOrder: [WebOrigin] = []
    private var cacheBytes = 0
    private var failedUntil: [WebOrigin: Date] = [:]
    private var failureOrder: [WebOrigin] = []
    private var inFlight: [WebOrigin: Task<CGImage?, Never>] = [:]

    /// A decoded, bounded raster image for the active page's conventional favicon, or `nil` when
    /// the URL or response cannot satisfy the privacy and resource limits above. Background
    /// prefetches may occupy only the active download slots; visible requests may queue behind
    /// those, up to the global admission bound.
    func favicon(for activeTabURL: String, prefetch: Bool = false) async -> CGImage? {
        guard !Task.isCancelled,
              let origin = WebOrigin(pageURL: activeTabURL)
        else { return nil }
        let now = Date()
        pruneFailures(at: now)

        if let cached = cache[origin] {
            touch(origin)
            return cached.image
        }

        if let deadline = failedUntil[origin], deadline > now {
            return nil
        }

        if let existing = inFlight[origin] {
            return await existing.value
        }

        guard !Task.isCancelled,
              inFlight.count < Self.maximumPendingDownloads,
              !prefetch || inFlight.count < Self.maximumPrefetchDownloads
        else { return nil }

        let request = Task.detached(priority: .utility) {
            await Self.downloadGate.acquire()
            let image = await Self.download(from: origin)
            await Self.downloadGate.release()
            return image
        }
        inFlight[origin] = request

        let image = await request.value
        inFlight.removeValue(forKey: origin)

        if let image {
            failedUntil.removeValue(forKey: origin)
            failureOrder.removeAll { $0 == origin }
            store(image, for: origin)
        } else {
            recordFailure(for: origin, at: Date())
        }
        return image
    }

    private func touch(_ origin: WebOrigin) {
        cacheOrder.removeAll { $0 == origin }
        cacheOrder.append(origin)
    }

    private func store(_ image: CGImage, for origin: WebOrigin) {
        let cost = image.bytesPerRow * image.height
        if let previous = cache.updateValue(CachedImage(image: image, cost: cost), forKey: origin) {
            cacheBytes -= previous.cost
        }
        cacheBytes += cost
        touch(origin)

        while cache.count > Self.maximumCacheEntries || cacheBytes > Self.maximumCacheBytes {
            guard let oldest = cacheOrder.first else { break }
            cacheOrder.removeFirst()
            if let evicted = cache.removeValue(forKey: oldest) {
                cacheBytes -= evicted.cost
            }
        }
    }

    private func pruneFailures(at now: Date) {
        let expired = failedUntil.compactMap { origin, deadline in
            deadline <= now ? origin : nil
        }
        guard !expired.isEmpty else { return }
        let expiredSet = Set(expired)
        for origin in expired {
            failedUntil.removeValue(forKey: origin)
        }
        failureOrder.removeAll { expiredSet.contains($0) }
    }

    private func recordFailure(for origin: WebOrigin, at now: Date) {
        failedUntil[origin] = now.addingTimeInterval(Self.failureCacheDuration)
        failureOrder.removeAll { $0 == origin }
        failureOrder.append(origin)

        while failedUntil.count > Self.maximumFailureCacheEntries,
              let oldest = failureOrder.first {
            failureOrder.removeFirst()
            failedUntil.removeValue(forKey: oldest)
        }
    }

    private static func download(from origin: WebOrigin) async -> CGImage? {
        // Most sites still answer here, and this avoids fetching even the origin root when they do.
        if let conventionalURL = origin.url(path: "/favicon.ico"),
           let image = await downloadImage(from: conventionalURL, origin: origin) {
            return image
        }

        var candidates: [IconCandidate] = []
        if let rootURL = origin.url(path: "/"),
           let document = await downloadResource(
               from: rootURL,
               origin: origin,
               maximumBytes: maximumHTMLBytes,
               allowTruncation: true,
               accept: "text/html,application/xhtml+xml;q=0.9"
           ),
           isHTML(document.response) {
            let html = String(decoding: document.data, as: UTF8.self)
            candidates.append(contentsOf: iconCandidates(
                in: html,
                baseURL: document.response.url ?? rootURL,
                origin: origin
            ))
        }

        // Some sites omit a declaration but publish one of these conventional same-origin files.
        let commonPaths = [
            "/favicon.png",
            "/apple-touch-icon.png",
            "/apple-touch-icon-precomposed.png",
        ]
        for (offset, path) in commonPaths.enumerated() {
            if let url = origin.url(path: path) {
                candidates.append(IconCandidate(url: url, score: 20 - offset, order: Int.max - 3 + offset))
            }
        }

        for candidate in orderedCandidates(candidates).prefix(maximumIconCandidates) {
            if let image = await downloadImage(from: candidate.url, origin: origin) {
                return image
            }
        }
        return nil
    }

    private static func downloadImage(from url: URL, origin: WebOrigin) async -> CGImage? {
        guard let resource = await downloadResource(
            from: url,
            origin: origin,
            maximumBytes: maximumResponseBytes,
            allowTruncation: false,
            accept: "image/avif,image/webp,image/png,image/*;q=0.9,*/*;q=0.1"
        ) else { return nil }

        if let mimeType = resource.response.mimeType?.lowercased(),
           !mimeType.hasPrefix("image/"),
           mimeType != "application/octet-stream",
           mimeType != "binary/octet-stream",
           mimeType != "application/x-icon",
           mimeType != "application/vnd.microsoft.icon" {
            return nil
        }
        return decodeBoundedRasterImage(resource.data)
    }

    /// Read one same-origin resource into bounded memory. HTML may stop at the byte ceiling because
    /// favicon declarations live in the document head; image responses must fit in full.
    private static func downloadResource(
        from url: URL,
        origin: WebOrigin,
        maximumBytes: Int,
        allowTruncation: Bool,
        accept: String
    ) async -> DownloadedResource? {
        guard WebOrigin(url: url) == origin else { return nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 1.5
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Vortexflow/1.0 favicon resolver", forHTTPHeaderField: "User-Agent")

        do {
            let delegate = SameOriginDelegate(origin: origin)
            let (bytes, rawResponse) = try await session.bytes(for: request, delegate: delegate)
            guard let response = rawResponse as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let finalURL = response.url,
                  WebOrigin(url: finalURL) == origin
            else { return nil }

            let expected = response.expectedContentLength
            if !allowTruncation, expected > Int64(maximumBytes) {
                return nil
            }

            var data = Data()
            if expected > 0 {
                data.reserveCapacity(min(maximumBytes, Int(expected)))
            }
            for try await byte in bytes {
                if data.count >= maximumBytes {
                    if allowTruncation { break }
                    return nil
                }
                data.append(byte)
            }

            guard !data.isEmpty else { return nil }
            return DownloadedResource(data: data, response: response)
        } catch {
            return nil
        }
    }

    private static func isHTML(_ response: HTTPURLResponse) -> Bool {
        guard let mimeType = response.mimeType?.lowercased() else { return true }
        return mimeType == "text/html" || mimeType == "application/xhtml+xml"
    }

    /// Extract favicon declarations from a bounded origin-root document. This is intentionally a
    /// narrow HTML scanner rather than a general parser: only `link`, `rel`, `href`, `type` and
    /// `sizes` matter, and every resolved URL is checked against the original origin again.
    private static func iconCandidates(
        in html: String,
        baseURL: URL,
        origin: WebOrigin
    ) -> [IconCandidate] {
        guard let linkExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var candidates: [IconCandidate] = []

        for (order, match) in linkExpression.matches(in: html, range: range).enumerated() {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let attributes = attributes(in: String(html[tagRange]))
            guard let relationship = attributes["rel"]?.lowercased(),
                  isIconRelationship(relationship),
                  let rawHref = attributes["href"]
            else { continue }

            if attributes["type"]?.lowercased().contains("svg") == true {
                continue
            }

            let href = decodeHTMLEntities(rawHref)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty,
                  href.count <= 4_096,
                  let absolute = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false)
            else { continue }

            components.fragment = nil
            guard let url = components.url, WebOrigin(url: url) == origin else { continue }

            candidates.append(
                IconCandidate(
                    url: url,
                    score: iconScore(
                        relationship: relationship,
                        type: attributes["type"],
                        sizes: attributes["sizes"]
                    ),
                    order: order
                )
            )
        }
        return candidates
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:.\-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#
        ) else { return [:] }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var attributes: [String: String] = [:]
        for match in expression.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = tag[nameRange].lowercased()
            for capture in 2...4 {
                if let valueRange = Range(match.range(at: capture), in: tag) {
                    attributes[name] = String(tag[valueRange])
                    break
                }
            }
        }
        return attributes
    }

    private static func isIconRelationship(_ relationship: String) -> Bool {
        let tokens = relationship.split(whereSeparator: { $0.isWhitespace })
        return tokens.contains("icon") || tokens.contains(where: {
            $0.hasPrefix("apple-touch-icon") || $0 == "mask-icon"
        })
    }

    private static func iconScore(
        relationship: String,
        type: String?,
        sizes: String?
    ) -> Int {
        let tokens = relationship.split(whereSeparator: { $0.isWhitespace })
        var score = tokens.contains("icon") ? 300 : 240

        let type = type?.lowercased() ?? ""
        if type.contains("png") { score += 60 }
        else if type.contains("webp") || type.contains("avif") { score += 55 }
        else if type.contains("icon") { score += 50 }
        else if type.contains("jpeg") { score += 20 }

        if let sizes = sizes?.lowercased() {
            for token in sizes.split(whereSeparator: { $0.isWhitespace }) {
                let dimensions = token.split(separator: "x", maxSplits: 1)
                if dimensions.count == 2,
                   let width = Int(dimensions[0]),
                   let height = Int(dimensions[1]),
                   width > 0,
                   height > 0 {
                    score += min(80, max(width, height) / 4)
                } else if token == "any" {
                    score += 5
                }
            }
        }
        return score
    }

    private static func orderedCandidates(_ candidates: [IconCandidate]) -> [IconCandidate] {
        var bestByURL: [URL: IconCandidate] = [:]
        for candidate in candidates {
            if let previous = bestByURL[candidate.url], previous.score >= candidate.score {
                continue
            }
            bestByURL[candidate.url] = candidate
        }
        return bestByURL.values.sorted {
            $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score
        }
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
    }

    /// Decode one safe representation and discard the source container. In particular, a small
    /// first ICO frame cannot smuggle unchecked larger frames into a later `NSImage(data:)` parse.
    private static func decodeBoundedRasterImage(_ data: Data) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              )
        else { return nil }

        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= maximumSourceRepresentations,
              let type = CGImageSourceGetType(source) as String?,
              isAllowedRasterType(type)
        else { return nil }

        var bestIndex: Int?
        var bestPixelCount = 0
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0,
                  height > 0,
                  width <= maximumSourceDimension,
                  height <= maximumSourceDimension,
                  width <= maximumSourcePixelCount / height
            else { continue }

            let pixelCount = width * height
            guard pixelCount <= maximumSourcePixelCount else { continue }
            if pixelCount > bestPixelCount {
                bestPixelCount = pixelCount
                bestIndex = index
            }
        }

        guard let bestIndex,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  bestIndex,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: renderedDimension,
                      kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary
              ),
              image.width > 0,
              image.height > 0,
              image.width <= renderedDimension,
              image.height <= renderedDimension
        else { return nil }

        return image
    }

    private static func isAllowedRasterType(_ type: String) -> Bool {
        let type = type.lowercased()
        return type == "public.png"
            || type == "public.jpeg"
            || type == "com.compuserve.gif"
            || type == "com.microsoft.ico"
            || type == "com.microsoft.bmp"
            || type == "public.tiff"
            || type == "org.webmproject.webp"
            || type == "public.heic"
            || type == "public.heif"
            || type == "public.avif"
    }

    /// The request's privacy boundary. Default URLSession redirect handling would otherwise let a
    /// site's `/favicon.ico` send the request to an unrelated analytics or favicon host.
    private final class SameOriginDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let origin: WebOrigin

        init(origin: WebOrigin) {
            self.origin = origin
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, WebOrigin(url: url) == origin else {
                completionHandler(nil)
                return
            }

            var safeRequest = request
            safeRequest.httpShouldHandleCookies = false
            safeRequest.setValue(nil, forHTTPHeaderField: "Cookie")
            safeRequest.setValue(nil, forHTTPHeaderField: "Authorization")
            completionHandler(safeRequest)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                // Never supply saved HTTP, proxy or client-certificate credentials for a passive
                // icon request.
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    private actor DownloadGate {
        private var permits: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) {
            permits = limit
        }

        func acquire() async {
            if permits > 0 {
                permits -= 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if waiters.isEmpty {
                permits += 1
            } else {
                waiters.removeFirst().resume()
            }
        }
    }

    private struct WebOrigin: Hashable, Sendable {
        let scheme: String
        let host: String
        let port: Int

        init?(pageURL: String) {
            guard let url = URL(string: pageURL) else { return nil }
            self.init(url: url)
        }

        init?(url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "https",
                  let host = components.host?.lowercased(),
                  !host.isEmpty,
                  components.user == nil,
                  components.password == nil
            else { return nil }

            let port = components.port ?? 443
            guard (1...65_535).contains(port) else { return nil }

            self.scheme = scheme
            self.host = host
            self.port = port
        }

        func url(path: String) -> URL? {
            guard path.hasPrefix("/") else { return nil }
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            if port != 443 {
                components.port = port
            }
            components.path = path
            return components.url
        }
    }
}
