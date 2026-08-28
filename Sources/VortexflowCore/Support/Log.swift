import Foundation
import os

/// Central logging. Uses the unified log so nothing is ever written to disk or a
/// network endpoint (Requirement 16.1, 16.2).
enum Log {
    private static let subsystem = "io.vortexflow.Vortexflow"

    static let trigger = Logger(subsystem: subsystem, category: "trigger")
    static let registry = Logger(subsystem: subsystem, category: "registry")
    static let thumbnails = Logger(subsystem: subsystem, category: "thumbnails")
    static let activation = Logger(subsystem: subsystem, category: "activation")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let app = Logger(subsystem: subsystem, category: "app")
}

/// Lightweight stopwatch used to check the performance budgets in Requirement 14
/// while developing. Emits at debug level, so it costs nothing in release logging.
struct Stopwatch {
    private let start = DispatchTime.now()
    private let label: String
    private let logger: Logger

    init(_ label: String, logger: Logger = Log.app) {
        self.label = label
        self.logger = logger
    }

    var elapsedMilliseconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    func log() {
        logger.debug("\(label, privacy: .public) took \(elapsedMilliseconds, format: .fixed(precision: 1)) ms")
    }
}
