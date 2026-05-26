import Darwin
import Foundation

@MainActor
enum MenuBarTerminationSignalHandler {
    private static var source: DispatchSourceSignal?

    static func install(terminationHandler: @escaping @MainActor () -> Void) {
        guard source == nil else {
            return
        }

        signal(SIGTERM, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource.setEventHandler {
            QRGoLogger.menuBarWarning("Received SIGTERM; requesting QRGo termination.")
            Task { @MainActor in
                terminationHandler()
            }
        }
        signalSource.resume()
        source = signalSource
    }
}
