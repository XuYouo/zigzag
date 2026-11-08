import AppKit
import WebKit
import Testing
@testable import Zigzag

/// Settings as a tab: its address names the section, and the section comes back from the address.
@MainActor
struct SettingsPageTests {
    @Test func eachSectionHasAnAddress() {
        #expect(SettingsPage.url(for: .general).absoluteString == "zigzag://settings")
        #expect(SettingsPage.url(for: .privacy).absoluteString == "zigzag://settings/privacy")
        for pane in SettingsPane.allCases {
            #expect(SettingsPage.pane(for: SettingsPage.url(for: pane)) == pane)
        }
    }

    @Test func readsTheAddressAPageLeaves() {
        // What history.replaceState leaves for General, and an address typed by hand.
        #expect(SettingsPage.pane(for: URL(string: "zigzag://settings/")) == .general)
        #expect(SettingsPage.pane(for: URL(string: "zigzag://settings/nothing")) == .general)
        #expect(SettingsPage.pane(for: URL(string: "zigzag://settings/shortcuts")) == .shortcuts)
    }

    @Test func onlyItsOwnAddressIsSettings() {
        #expect(SettingsPage.isSettings(URL(string: "zigzag://settings/spaces")))
        #expect(!SettingsPage.isSettings(URL(string: "zigzag://history")))
        #expect(!SettingsPage.isSettings(URL(string: "https://settings.example.com")))
        #expect(!HistoryPage.isHistory(URL(string: "zigzag://settings")))
        #expect(HistoryPage.isInternal(URL(string: "zigzag://settings")))
    }

    @Test func lateAddressEchoesCannotSelectAnOlderPane() {
        var mirror = SettingsPage.AddressMirror()
        #expect(mirror.select(.appearance) == SettingsPage.url(for: .appearance))
        #expect(mirror.select(.privacy) == SettingsPage.url(for: .privacy))
        #expect(mirror.acceptedAddress(SettingsPage.url(for: .appearance)) == nil)
        #expect(mirror.acceptedAddress(SettingsPage.url(for: .privacy)) == SettingsPage.url(for: .privacy))
        // An old echo cannot take over even after the latest one has already arrived.
        #expect(mirror.acceptedAddress(SettingsPage.url(for: .appearance)) == nil)
        _ = mirror.select(.general)
        #expect(mirror.acceptedAddress(URL(string: "zigzag://settings/")!) == SettingsPage.url)
    }

    @Test func realNavigationMakesTheAddressAuthoritativeAgain() {
        var mirror = SettingsPage.AddressMirror()
        _ = mirror.select(.privacy)
        mirror.navigationStarted()
        // Reload, Back/Forward, and typed deep links use the same reset before following their loaded address.
        for pane in SettingsPane.allCases {
            let address = SettingsPage.url(for: pane)
            #expect(mirror.acceptedAddress(address) == address)
        }
        let outside = URL(string: "https://example.com/")!
        #expect(mirror.acceptedAddress(outside) == outside)
    }

    @Test func rapidNativeSelectionIgnoresWebKitReplaceStateEchoes() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(SettingsFixture(), forURLScheme: HistoryPage.scheme)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.load(URLRequest(url: SettingsPage.url))
        try await waitForFixture(in: webView)
        let state = EchoState()
        let navigation = FixtureNavigation(state: state)
        webView.navigationDelegate = navigation
        let token = webView.observe(\.url, options: [.new]) { webView, _ in
            MainActor.assumeIsolated {
                state.followAddress(webView.url)
            }
        }
        defer { token.invalidate(); webView.stopLoading(); webView.navigationDelegate = nil }

        // Queue both native choices before letting the web process reply. Without the mirror, the first URL
        // echo visibly sends Privacy back to Appearance, then the next echo sends it to Privacy again.
        for pane in [SettingsPane.appearance, .privacy] {
            _ = state.mirror.select(pane)
            state.shown = pane
            webView.evaluateJavaScript("history.replaceState(null, '', '/\(pane.path)')", completionHandler: nil)
        }
        let finalPath = try await evaluate("location.pathname", in: webView)
        #expect(finalPath == "/privacy")
        for _ in 0..<200 {
            if state.reported.contains(.privacy) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.policyCalls == 0)
        #expect(state.reported.contains(.privacy))
        #expect(state.reversals.isEmpty)
        #expect(state.shown == .privacy)

        // A real navigation is not an echo. The loaded section must take over as it does before this fix.
        webView.load(URLRequest(url: SettingsPage.url(for: .shortcuts)))
        for _ in 0..<200 {
            if state.shown == .shortcuts { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.shown == .shortcuts)
        #expect(state.policyCalls > 0)
        #expect(state.commits > 0)
    }

    private final class EchoState {
        var mirror = SettingsPage.AddressMirror()
        var shown = SettingsPane.general
        var reported: [SettingsPane] = []
        var reversals: [SettingsPane] = []
        var policyCalls = 0
        var commits = 0

        func followAddress(_ reported: URL?) {
            guard let reported else { return }
            self.reported.append(SettingsPage.pane(for: reported))
            guard let accepted = mirror.acceptedAddress(reported) else { return }
            let pane = SettingsPage.pane(for: accepted)
            if shown != pane { reversals.append(pane); shown = pane }
        }
    }

    /// Match Tab's real navigation boundary; replaceState must not clear the echo gate through this delegate.
    private final class FixtureNavigation: NSObject, WKNavigationDelegate {
        let state: EchoState
        init(state: EchoState) { self.state = state }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            if action.targetFrame?.isMainFrame ?? true {
                state.policyCalls += 1
                state.mirror.navigationStarted()
            }
            return (.allow, preferences)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // Like Tab.didCommit: a URL can be reported before the async policy decision clears the mirror.
            // Once the navigation actually commits, its address is followed again and becomes authoritative.
            state.commits += 1
            state.followAddress(webView.url)
        }
    }

    private final class SettingsFixture: NSObject, WKURLSchemeHandler {
        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url else { return }
            let data = Data("<!doctype html><title>Settings fixture</title>".utf8)
            task.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
            task.didReceive(data)
            task.didFinish()
        }
        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
    }

    private func waitForFixture(in webView: WKWebView) async throws {
        for _ in 0..<200 {
            if (try? await evaluate("document.title", in: webView)) == "Settings fixture" { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The local Settings fixture did not load")
        throw URLError(.timedOut)
    }

    private func evaluate(_ source: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as? String ?? "") }
            }
        }
    }

}
