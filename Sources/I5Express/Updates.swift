import AppKit
import Sparkle

/// Checks GitHub for a new version every 6 hours and installs it right away.
@MainActor
final class Updates: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    /// Nil when running outside the .app, since there's no feed to check
    static func make() -> Updates? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") == nil ? nil : Updates()
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var automatic: Bool {
        get { controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // A menu bar app hardly ever quits, so install and relaunch now instead of waiting for a quit
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }
}
