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
        if identifier == BackgroundDownloadTransport.sessionIdentifier {
            BackgroundDownloadTransport.shared.setBackgroundCompletionHandler(completionHandler)
        } else {
            completionHandler()
        }
    }
}
