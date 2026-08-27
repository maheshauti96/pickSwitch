import AppKit
import Foundation

/// Finds applications in macOS's standard installation locations.
///
/// Scanning is intentionally synchronous: the controller owns where it runs and calls this on
/// a dedicated utility queue at launch. Results are cached for the process lifetime because an
/// Applications directory changing during one Vortexflow session is uncommon, while walking it
/// every time the overlay appears would put disk I/O on a latency-sensitive interaction.
final class ApplicationCatalog: @unchecked Sendable {

    private let lock = NSLock()
    private var cache: [LaunchableApplication]?

    func applications() -> [LaunchableApplication] {
        lock.lock()
        let cached = cache
        lock.unlock()
        if let cached { return cached }

        let scanned = scan()

        lock.lock()
        if cache == nil {
            cache = scanned
        }
        let result = cache ?? scanned
        lock.unlock()
        return result
    }

    /// Remove a bundle that Launch Services confirmed can no longer be opened.
    func remove(_ application: LaunchableApplication) {
        lock.lock()
        cache?.removeAll { $0.id == application.id }
        lock.unlock()
    }

    private func scan() -> [LaunchableApplication] {
        let fileManager = FileManager.default
        var applications: [LaunchableApplication] = []
        var claimedApplications: Set<String> = []

        for root in roots(fileManager: fileManager) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    Log.registry.debug(
                        "could not inspect application directory at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    return true
                }
            ) else { continue }

            for case let candidate as URL in enumerator {
                guard candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }
                // Be explicit even though `skipsPackageDescendants` normally does this: helper
                // applications inside a bundle are implementation details, not launch results.
                enumerator.skipDescendants()

                guard let application = application(at: candidate, workspace: .shared) else {
                    continue
                }

                // Duplicate bundle identifiers are usually an alias or an older copy. Prefer
                // the first standard location, while apps without an identifier stay distinct
                // by their canonical bundle path.
                let claim = application.bundleIdentifier
                    .map { "bundle:\($0.lowercased())" }
                    ?? "path:\(application.bundleURL.path.lowercased())"
                guard claimedApplications.insert(claim).inserted else { continue }
                applications.append(application)
            }
        }

        return applications.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.bundleURL.path.localizedStandardCompare(rhs.bundleURL.path) == .orderedAscending
        }
    }

    private func roots(fileManager: FileManager) -> [URL] {
        // User applications come first so an explicitly installed per-user copy wins over an
        // older machine-wide copy with the same bundle identifier.
        let domains: [FileManager.SearchPathDomainMask] = [
            .userDomainMask,
            .localDomainMask,
            .systemDomainMask,
        ]
        var candidates = domains.flatMap {
            fileManager.urls(for: .applicationDirectory, in: $0)
        }
        // Small Apple utilities such as Archive Utility live outside /System/Applications.
        candidates.append(URL(fileURLWithPath: "/System/Library/CoreServices/Applications"))
        candidates.append(URL(fileURLWithPath: "/Library/CoreServices/Applications"))

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let canonical = candidate.standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seen.insert(canonical.path).inserted else {
                return nil
            }
            return canonical
        }
    }

    private func application(at url: URL, workspace: NSWorkspace) -> LaunchableApplication? {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let bundle = Bundle(url: canonical), bundle.executableURL != nil else { return nil }

        let localized = bundle.localizedInfoDictionary
        let unlocalized = bundle.infoDictionary
        let name = nonEmptyString(localized?["CFBundleDisplayName"])
            ?? nonEmptyString(localized?["CFBundleName"])
            ?? nonEmptyString(unlocalized?["CFBundleDisplayName"])
            ?? nonEmptyString(unlocalized?["CFBundleName"])
            ?? canonical.deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return nil }

        return LaunchableApplication(
            name: name,
            bundleIdentifier: bundle.bundleIdentifier,
            bundleURL: canonical,
            icon: workspace.icon(forFile: canonical.path)
        )
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
