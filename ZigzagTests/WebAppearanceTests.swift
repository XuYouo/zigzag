import AppKit
import WebKit
import Testing
@testable import Zigzag

@MainActor
struct WebAppearanceTests {
    @Test func onlyWebDocumentsUseTheBackdrop() {
        #expect(WebAppearance.supports(URL(string: "https://example.com/article")))
        #expect(!WebAppearance.supports(URL(string: "https://example.com/document.PDF")))
        #expect(!WebAppearance.supports(URL(string: "file:///tmp/document.html")))
        #expect(!WebAppearance.supports(URL(string: "webkit-extension://example/options.html")))
        #expect(!WebAppearance.supports(URL(string: "zigzag://settings")))
    }

    @Test func pageCanvasChangesWithoutFadingContentAndRestoresCurrentSiteStyles() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString("""
        <!doctype html><html><head><style>
        html, body { margin: 0; min-height: 100%; background: rgb(250, 250, 250); }
        #shell { min-height: 100vh; background: rgb(250, 250, 250); }
        #card { width: 200px; height: 120px; background: white; }
        input { background-color: white; color: black; }
        </style></head><body><div id="shell"><p id="fixture">Readable text</p>
        <div id="card">A card</div><input id="password" type="password" value="fixture-only">
        <img id="picture" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">
        </div></body></html>
        """, baseURL: URL(string: "https://appearance.example/"))
        var ready = false
        for _ in 0..<200 {
            if (try? await script("document.getElementById('fixture') ? 'ready' : ''", in: webView)) == "ready" {
                ready = true; break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(ready, "The local WebKit fixture did not load")
        let baseline = try await script("document.body.getAttribute('style') || ''", in: webView)
        _ = try await script(WebAppearance.source(enabled: true, opacity: 0.55) + "; 'ok'", in: webView)
        #expect(try await script("getComputedStyle(document.documentElement).backgroundColor", in: webView) == "rgba(250, 250, 250, 0.55)")
        #expect(try await script("getComputedStyle(document.body).backgroundColor", in: webView) == "rgba(0, 0, 0, 0)")
        #expect(try await script("getComputedStyle(document.getElementById('shell')).backgroundColor", in: webView) == "rgba(0, 0, 0, 0)")
        #expect(try await script("['fixture', 'password', 'picture'].map(id => getComputedStyle(document.getElementById(id)).opacity).join(',')", in: webView) == "1,1,1")
        #expect(try await script("getComputedStyle(document.getElementById('card')).backgroundColor", in: webView) == "rgb(255, 255, 255)")
        #expect(try await script("document.getElementById('password').value", in: webView) == "fixture-only")

        // A SPA replaces its shell and changes the authored background while the appearance effect is enabled.
        _ = try await script("""
        Object.defineProperty(document, 'hidden', { configurable: true, value: false });
        document.body.style.backgroundColor = 'rgb(230, 230, 230)';
        const replacement = document.createElement('div');
        replacement.id = 'new-shell'; replacement.style.minHeight = '100vh';
        replacement.style.backgroundColor = 'rgb(230, 230, 230)';
        const previous = document.getElementById('shell');
        previous.replaceWith(replacement); replacement.append(previous);
        'ok'
        """, in: webView)
        var observed = false
        for _ in 0..<50 {
            if try await script("getComputedStyle(document.getElementById('new-shell')).backgroundColor", in: webView) == "rgba(0, 0, 0, 0)" {
                observed = true; break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(observed, "New SPA shells should adopt the appearance without a reload or settings change")
        #expect(try await script("getComputedStyle(document.documentElement).backgroundColor", in: webView) == "rgba(230, 230, 230, 0.55)")
        // Explicit updates apply immediately, independently of whether an unattached test page is visible.
        _ = try await script(WebAppearance.source(enabled: true, opacity: 0.4) + "; 'ok'", in: webView)
        #expect(try await script("getComputedStyle(document.documentElement).backgroundColor", in: webView) == "rgba(230, 230, 230, 0.4)")
        _ = try await script(WebAppearance.source(enabled: false, opacity: 0.4) + "; 'ok'", in: webView)
        #expect(try await script("getComputedStyle(document.body).backgroundColor", in: webView) == "rgb(230, 230, 230)")
        #expect(try await script("document.getElementById('shell').getAttribute('style') || ''", in: webView) == baseline)
        #expect(try await script("getComputedStyle(document.getElementById('new-shell')).backgroundColor", in: webView) == "rgb(230, 230, 230)")
        #expect(try await script("getComputedStyle(document.documentElement).backgroundColor", in: webView) == "rgb(250, 250, 250)")
    }

    @Test func forumGuttersAndTransparentRowsReturnToAnOpaqueContinuousCanvas() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString("""
        <!doctype html><title>Forum canvas fixture</title><style>
        html, body { margin: 0; background: white; }
        header { height: 64px; background: white; }
        .wrap { padding: 0 12px; }
        table { border-collapse: collapse; width: 100%; }
        td { height: 64px; padding: 0; background: white; border-bottom: 1px solid #ddd; }
        .transparent-row td { background: transparent; }
        </style><header>Forum</header><main class="wrap"><table><tbody>
        <tr><td>First topic</td></tr><tr><td>Second topic</td></tr>
        <tr class="transparent-row"><td>Selected topic</td></tr>
        <tr><td>Fourth topic</td></tr><tr><td>Fifth topic</td></tr>
        </tbody></table></main>
        """, baseURL: URL(string: "https://forum.example/"))
        var ready = false
        for _ in 0..<200 {
            if (try? await script("document.title", in: webView)) == "Forum canvas fixture" { ready = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(ready)
        let geometry = "JSON.stringify(['html', 'body', '.wrap', 'table', '.transparent-row'].map(s => { const r = document.querySelector(s).getBoundingClientRect(); return [r.x,r.y,r.width,r.height]; }))"
        let originalGeometry = try await script(geometry, in: webView)
        let original = try await bitmap(of: webView)

        // Wallpaper is opt-in through the background mode. Reproduce the former glass-mode holes: native
        // canvas is clear while the forum's white rows stay opaque and its gutters/transparent row reveal it.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        _ = try await script(WebAppearance.source(enabled: true, opacity: 0.35) + "; 'ok'", in: webView)
        let wallpaper = try await bitmap(of: webView)
        #expect(try pixel(wallpaper, x: 4, y: 160).alphaComponent < 0.99)
        #expect(try pixel(wallpaper, x: 400, y: 160).alphaComponent == 1)
        #expect(try await script(geometry, in: webView) == originalGeometry)

        // Glass mode disables the web effect and restores the native canvas, including an already-loaded page.
        _ = try await script(WebAppearance.source(enabled: false, opacity: 0.35) + "; 'ok'", in: webView)
        webView.setValue(true, forKey: "drawsBackground")
        webView.underPageBackgroundColor = nil
        let restored = try await bitmap(of: webView)
        for point in [(4, 160), (796, 160), (400, 160), (400, 224)] {
            let before = try pixel(original, x: point.0, y: point.1)
            let after = try pixel(restored, x: point.0, y: point.1)
            #expect(after.alphaComponent == 1)
            #expect(abs(after.redComponent - before.redComponent) < 0.01)
            #expect(abs(after.greenComponent - before.greenComponent) < 0.01)
            #expect(abs(after.blueComponent - before.blueComponent) < 0.01)
        }
        #expect(try await script(geometry, in: webView) == originalGeometry)
    }

    /// Actual WebKit pixels, without opening or automating a browser window.
    private func bitmap(of webView: WKWebView) async throws -> NSBitmapImageRep {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: CocoaError(.coderInvalidValue)) }
            }
        }
        return try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    }

    private func pixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        // Snapshot scale follows the Mac's display; sample CSS-point coordinates on either 1x or 2x.
        try #require(bitmap.colorAt(x: x * bitmap.pixelsWide / 800, y: y * bitmap.pixelsHigh / 600)?.usingColorSpace(.sRGB))
    }

    private func script(_ source: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value as? String ?? "")
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
}
