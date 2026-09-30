import Foundation
import Testing

/// Checks the host app's generated Info.plist. Unit tests run inside the app,
/// so `Bundle.main` is the app bundle.
struct AppConfigurationTests {
    @Test func displayNameIs4096() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "4096")
    }

    @Test func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.crypticswarm.game4096")
    }
}
