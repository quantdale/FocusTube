import SwiftUI
import UIKit
@_exported import FocusTubeCore

@main
struct FocusTubeApp: App {
    @UIApplicationDelegateAdaptor(FocusTubeAppDelegate.self) private var appDelegate
    /// Created once per process; RootView reads dependencies from here instead
    /// of building them in its own re-evaluated init.
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
