/// Purpose:
/// App entry point for the utility that writes synthetic sleep and HRV data into Apple Health.
///
/// Responsibilities:
/// Keep startup wiring minimal and hand control to the root SwiftUI screen.
///
/// Non-Goals:
/// Business logic and HealthKit access stay out of this file.
import SwiftUI

@main
struct GenerateSleepDataApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
