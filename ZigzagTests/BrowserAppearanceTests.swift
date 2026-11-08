import AppKit
import Testing
@testable import Zigzag

/// Preferences are restored after each test; no wallpaper files or browser library are created or changed.
@Suite(.serialized)
@MainActor
struct BrowserAppearanceTests {
    private let keys = ["background", "material", "transparency", "wallpaperOpacity", "wallpaperBlur",
                        "wallpaperShade", "pageOpacity", "onWebsites"]

    private func withFreshPreferences(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        let names = keys.map { "Appearance." + $0 }
        for name in names { defaults.removeObject(forKey: name) }
        defer {
            for name in names {
                if let value = domain[name] { defaults.set(value, forKey: name) }
                else { defaults.removeObject(forKey: name) }
            }
            BrowserAppearance.changed.send()
        }
        body()
    }

    @Test func newProfileUsesGlassAndReadablePageDefaults() {
        withFreshPreferences {
            #expect(BrowserAppearance.background == .glass)
            #expect(BrowserAppearance.material == .sidebar)
            #expect(BrowserAppearance.transparency == 0.78)
            #expect(BrowserAppearance.wallpaperOpacity == 0.85)
            #expect(BrowserAppearance.wallpaperBlur == 0.15)
            #expect(BrowserAppearance.wallpaperShade == 0.18)
            #expect(BrowserAppearance.pageOpacity == 0.82)
            #expect(BrowserAppearance.onWebsites)
            // Native glass must not turn a site's padding or transparent rows into holes in its canvas.
            #expect(!BrowserAppearance.translucentPages)
            #expect(BrowserAppearance.translucentSurfaces == !BrowserAppearance.reducesTransparency)
        }
    }

    @Test func unknownStoredOptionsFallBackAndValidChoicesPersist() {
        withFreshPreferences {
            let defaults = UserDefaults.standard
            defaults.set("removed-background", forKey: "Appearance.background")
            defaults.set("removed-material", forKey: "Appearance.material")
            #expect(BrowserAppearance.background == .glass)
            #expect(BrowserAppearance.material == .sidebar)
            BrowserAppearance.background = .space
            BrowserAppearance.material = .hud
            BrowserAppearance.onWebsites = false
            #expect(defaults.string(forKey: "Appearance.background") == "space")
            #expect(defaults.string(forKey: "Appearance.material") == "hud")
            #expect(defaults.object(forKey: "Appearance.onWebsites") as? Bool == false)
            #expect(BrowserAppearance.background == .space)
            #expect(BrowserAppearance.material == .hud)
            #expect(!BrowserAppearance.onWebsites)
        }
    }

    @Test func effectAmountsRejectNonfiniteWritesAndClampOutOfRangeValues() {
        withFreshPreferences {
            var changes = 0
            let token = BrowserAppearance.changed.observe { changes += 1 }
            defer { token.cancel() }
            BrowserAppearance.setAmount(0.4, key: "pageOpacity")
            #expect(BrowserAppearance.pageOpacity == 0.4)
            #expect(UserDefaults.standard.double(forKey: "Appearance.pageOpacity") == 0.4)
            for value in [Double.nan, Double.infinity, -Double.infinity] {
                BrowserAppearance.setAmount(value, key: "pageOpacity")
                #expect(BrowserAppearance.pageOpacity == 0.4)
            }
            #expect(changes == 1)
            BrowserAppearance.setAmount(-0.2, key: "pageOpacity")
            #expect(BrowserAppearance.pageOpacity == 0)
            BrowserAppearance.setAmount(1.5, key: "pageOpacity")
            #expect(BrowserAppearance.pageOpacity == 1)
            #expect(changes == 3)

            // Imported preferences may be malformed without passing through our setters.
            UserDefaults.standard.set("invalid", forKey: "Appearance.wallpaperBlur")
            #expect(BrowserAppearance.wallpaperBlur == 0.15)
            UserDefaults.standard.set(-2.0, forKey: "Appearance.wallpaperBlur")
            #expect(BrowserAppearance.wallpaperBlur == 0)
            UserDefaults.standard.set(8.0, forKey: "Appearance.wallpaperBlur")
            #expect(BrowserAppearance.wallpaperBlur == 1)
        }
    }

    @Test func opaqueModesAndSystemAccessibilityTakePriorityOverPageTransparency() {
        withFreshPreferences {
            // Read the actual system setting, without changing it or requiring a particular host setup.
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            #expect(BrowserAppearance.reducesTransparency == reduced)
            for background in ["glass", "wallpaper"] {
                UserDefaults.standard.set(background, forKey: "Appearance.background")
                #expect(BrowserAppearance.translucentPages == (background == "wallpaper" && !reduced))
                #expect(BrowserAppearance.translucentSurfaces == !reduced)
                #expect(BrowserAppearance.surfaceColor.alphaComponent == (reduced ? 1 : 0.82))
            }
            UserDefaults.standard.set("space", forKey: "Appearance.background")
            #expect(!BrowserAppearance.translucentPages)
            #expect(BrowserAppearance.surfaceColor.alphaComponent == 1)
            UserDefaults.standard.set("wallpaper", forKey: "Appearance.background")
            UserDefaults.standard.set(false, forKey: "Appearance.onWebsites")
            #expect(!BrowserAppearance.translucentPages)
            #expect(BrowserAppearance.translucentSurfaces == !reduced)
            UserDefaults.standard.set(true, forKey: "Appearance.onWebsites")
            UserDefaults.standard.set(1.0, forKey: "Appearance.pageOpacity")
            #expect(!BrowserAppearance.translucentPages)
            #expect(BrowserAppearance.surfaceColor.alphaComponent == 1)
        }
    }

    @Test func appearanceHasItsOwnRestorableSettingsAddress() {
        let url = SettingsPage.url(for: .appearance)
        #expect(url.absoluteString == "zigzag://settings/appearance")
        #expect(SettingsPage.isSettings(url))
        #expect(SettingsPage.pane(for: url) == .appearance)
        #expect(SettingsPage.pane(for: URL(string: "zigzag://settings/appearance/")) == .appearance)
    }
}
