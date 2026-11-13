import UIKit

/// Opens Duo Mobile. Duo doesn't document it, but Duo Mobile handles `duo://` (checked on an
/// iPhone running Duo Mobile 4.125). `duo` is listed under LSApplicationQueriesSchemes so
/// canOpenURL can tell whether Duo Mobile is installed.
@MainActor
enum DuoLauncher {
    private static let url = URL(string: "duo://")!

    static var isInstalled: Bool { UIApplication.shared.canOpenURL(url) }

    static func open() {
        guard isInstalled else { return }
        UIApplication.shared.open(url)
    }
}
