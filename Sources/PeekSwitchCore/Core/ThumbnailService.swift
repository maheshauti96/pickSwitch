import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Window thumbnails via ScreenCaptureKit (Requirement 9).
///
/// ## Delivery model
///
/// Captures are fired per window and delivered through `onImage` as each one
/// completes, rather than awaited as a batch. The overlay is already on screen by
/// then showing app icons (Requirement 9.3), and cards fill in underneath. A batch
/// `await` would put the slowest window on the critical path and blow the 150 ms
/// presentation budget.
///
/// Requests are issued in MRU order, so the cards the user is most likely to pick
/// resolve first (Requirement 9.4).
///
/// ## The "live stream" for the selected card
///
/// Requirement 9.6 asks for a live stream of the selected card at 10 fps or less.
/// This is implemented as a 10 Hz repeating re-capture rather than a long-lived
/// `SCStream`. Reasons:
///
/// - An `SCStream` needs a delegate, an output queue, `CMSampleBuffer` to `CGImage`
///   conversion and careful teardown. For a surface that is visible for a second or
///   two at a time, that is a lot of moving parts to leak or crash in.
/// - Start-up latency for `SCStream` is real; a re-capture timer shows its first
///   updated frame sooner.
/// - Requirement 9.7's "at most one active Live_Stream" maps cleanly onto "at most
///   one active timer", which is trivially auditable.
///
/// The tradeoff is higher per-frame cost than a true stream. It is bounded by only
/// ever running for the single selected card while the overlay is open, and it is
/// torn down within 200 ms of dismissal (Requirement 8.5). Swapping in `SCStream`
/// later is a change behind this same interface.
actor ThumbnailService {

    /// Cheap identity for a capture generation. Results from a previous overlay
    /// presentation are discarded rather than applied to the new one.
    private var generation: UInt64 = 0

    private var shareableContentCache: SCShareableContent?
    private var shareableContentCachedAt: Date?
    /// Window sets change constantly, but not within one overlay presentation.
    private static let shareableContentTTL: TimeInterval = 0.5

    private var liveStreamTask: Task<Void, Never>?
    private var liveStreamWindowID: CGWindowID?

    // MARK: - Still captures

    /// Begin a new capture generation and return its token. Any in-flight work from
    /// an older generation becomes a no-op.
    func beginGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    /// Requirement 9.1, 9.2, 9.4, 9.5.
    ///
    /// - Parameters:
    ///   - entries: displayed windows, already in MRU order.
    ///   - scale: backing scale factor of the display the overlay is on.
    ///   - token: generation token from `beginGeneration()`.
    ///   - onImage: invoked on the main actor per successful capture.
    func captureStills(
        for entries: [WindowEntry],
        scale: CGFloat,
        token: UInt64,
        onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        guard let content = await shareableContent() else {
            Log.thumbnails.info("no shareable content; cards keep their app icons")
            return
        }
        guard token == generation else { return }

        let windowsByID = Dictionary(
            content.windows.map { (CGWindowID($0.windowID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let pixelSize = CGSize(
            width: StripLayout.cardSize.width * scale,
            height: StripLayout.thumbnailHeight * scale
        )

        // Bounded concurrency. Unbounded task-per-window against 25 windows makes
        // the window server the bottleneck and slows every capture down.
        let maxConcurrent = 4
        var index = 0

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            while index < entries.count {
                if running >= maxConcurrent {
                    await group.next()
                    running -= 1
                }
                let entry = entries[index]
                index += 1

                // Minimized windows have no on-screen surface to capture; the card
                // keeps its app icon (Requirement 9.9 path).
                guard !entry.isMinimized, let scWindow = windowsByID[entry.windowID] else { continue }

                running += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    guard let image = await Self.captureImage(
                        of: scWindow,
                        pixelSize: pixelSize
                    ) else { return }
                    guard await self.isCurrent(token) else { return }
                    await MainActor.run {
                        onImage(entry.windowID, image)
                    }
                }
            }
            await group.waitForAll()
        }
    }

    /// Higher-resolution capture for the selected card (Requirement 3.4): at least
    /// twice the linear pixel dimensions of an unselected thumbnail.
    func captureSelectedPreview(
        for entry: WindowEntry,
        scale: CGFloat,
        token: UInt64,
        onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        guard !entry.isMinimized else { return }
        guard let content = await shareableContent(), token == generation else { return }
        guard let scWindow = content.windows.first(where: { CGWindowID($0.windowID) == entry.windowID })
        else { return }

        let pixelSize = CGSize(
            width: StripLayout.cardSize.width * scale * 2,
            height: StripLayout.thumbnailHeight * scale * 2
        )
        guard let image = await Self.captureImage(of: scWindow, pixelSize: pixelSize) else { return }
        guard token == generation else { return }
        await MainActor.run { onImage(entry.windowID, image) }
    }

    // MARK: - Live refresh of the selected card

    /// Requirement 9.6, 9.7, 9.8. Starting a stream implicitly stops the previous
    /// one, which is what keeps the "at most one" invariant true by construction.
    func startLiveStream(
        for entry: WindowEntry,
        scale: CGFloat,
        token: UInt64,
        onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) {
        stopLiveStream()
        guard !entry.isMinimized else { return }

        liveStreamWindowID = entry.windowID
        liveStreamTask = Task { [weak self] in
            // 10 fps ceiling.
            let frameInterval = Duration.milliseconds(100)
            while !Task.isCancelled {
                try? await Task.sleep(for: frameInterval)
                if Task.isCancelled { return }
                guard let self, await self.isCurrent(token) else { return }
                await self.captureSelectedPreview(
                    for: entry,
                    scale: scale,
                    token: token,
                    onImage: onImage
                )
            }
        }
    }

    func stopLiveStream() {
        liveStreamTask?.cancel()
        liveStreamTask = nil
        liveStreamWindowID = nil
    }

    var hasActiveLiveStream: Bool { liveStreamTask != nil }

    /// Requirement 8.5, 8.6: nothing survives dismissal.
    func teardown() {
        stopLiveStream()
        generation &+= 1
        shareableContentCache = nil
        shareableContentCachedAt = nil
    }

    // MARK: - Private

    private func isCurrent(_ token: UInt64) -> Bool { token == generation }

    private func shareableContent() async -> SCShareableContent? {
        if let cache = shareableContentCache,
           let cachedAt = shareableContentCachedAt,
           Date().timeIntervalSince(cachedAt) < Self.shareableContentTTL {
            return cache
        }
        do {
            // `onScreenWindowsOnly: false` so the set still includes windows that
            // are occluded; those are capturable even though minimized ones are not.
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            shareableContentCache = content
            shareableContentCachedAt = Date()
            return content
        } catch {
            // Overwhelmingly this means Screen Recording is not granted
            // (Requirement 10.8).
            Log.thumbnails.info("SCShareableContent unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func captureImage(of window: SCWindow, pixelSize: CGSize) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()

        // Preserve the source aspect ratio (Requirement 9.5) by fitting the window
        // into the thumbnail box rather than stretching it.
        let sourceSize = window.frame.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let fitScale = min(
            pixelSize.width / sourceSize.width,
            pixelSize.height / sourceSize.height
        )
        configuration.width = max(1, Int((sourceSize.width * fitScale).rounded()))
        configuration.height = max(1, Int((sourceSize.height * fitScale).rounded()))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            Log.thumbnails.debug("capture failed for window \(window.windowID): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
