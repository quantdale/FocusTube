import UIKit
import FocusTubeCore

/// Minimal UIKit app delegate so the system can wake FocusTube when a
/// background `URLSession` finishes transferring while the app is suspended, and
/// hand back the completion handler the system expects once all events are
/// delivered.
final class FocusTubeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // ADR-0007: downloads were removed; a leftover background session
        // from an older build is acknowledged immediately.
        completionHandler()
    }
}
