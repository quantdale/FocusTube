import SwiftUI
import UIKit
@_exported import FocusTubeCore

@main
struct FocusTubeApp: App {
    @UIApplicationDelegateAdaptor(FocusTubeAppDelegate.self) private var appDelegate
    /// Created once per process; RootView reads dependencies from here instead
    /// of building them in its own re-evaluated init. `make` selects production
    /// or DEBUG UI-test fixtures from launch arguments.
    @State private var dependencies = AppDependencies.make()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
