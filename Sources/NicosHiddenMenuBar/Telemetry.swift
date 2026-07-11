import Foundation
import OSLog

enum HiddenMenuBarTelemetry {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.nstranquist.nicos-hidden-menubar"

    static let appLifecycle = Logger(subsystem: subsystem, category: "AppLifecycle")
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
    static let windowing = Logger(subsystem: subsystem, category: "Windowing")
    static let commandExecution = Logger(subsystem: subsystem, category: "CommandExecution")
}
