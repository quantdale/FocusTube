import SwiftUI
import UIKit
@_exported import FocusTubeCore

@main
struct FocusTubeApp: App {
    @UIApplicationDelegateAdaptor(FocusTubeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
