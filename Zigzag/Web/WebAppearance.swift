import AppKit
import WebKit

/// Lets a page's canvas reveal the native window background. Wallpaper data never enters the web process.
final class WebAppearance {
    private weak var webView: BrowserWebView?
    private var token: SignalToken?
    private var accessibilityToken: NSObjectProtocol?
    private struct State: Equatable {
        let enabled: Bool
        let opacity: Double
    }
    private var lastApplied: State?

    init(_ webView: BrowserWebView) {
        self.webView = webView
        token = BrowserAppearance.changed.observe { [weak self] in self?.refresh() }
        accessibilityToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh(force: true)
    }

    isolated deinit {
        if let accessibilityToken { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityToken) }
    }

    static func supports(_ url: URL?) -> Bool {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return url.pathExtension.lowercased() != "pdf"
    }

    func refresh(force: Bool = false) {
        guard let webView else { return }
        let enabled = BrowserAppearance.translucentPages && Self.supports(webView.url ?? webView.owner?.url)
            && webView.owner?.pdfViewer == nil
        // WebKit has no public macOS canvas switch. Check the same optional setter Peek already uses before
        // invoking it; an OS that removes it keeps a normal opaque canvas instead of risking an exception.
        let canClear = webView.responds(to: NSSelectorFromString("setDrawsBackground:"))
            || webView.responds(to: NSSelectorFromString("_setDrawsBackground:"))
        let state = State(enabled: enabled && canClear, opacity: enabled && canClear ? BrowserAppearance.pageOpacity : 1)
        // Window-only sliders do not change the webpage. Every open tab hears the same signal, so avoid a
        // JavaScript round trip and DOM scan in each of them unless its effective page appearance changed.
        guard force || state != lastApplied else { return }
        lastApplied = state
        if canClear { webView.setValue(!state.enabled, forKey: "drawsBackground") }
        webView.underPageBackgroundColor = state.enabled ? .clear : nil
        webView.evaluateJavaScript(Self.source(enabled: state.enabled, opacity: state.opacity),
                                   in: nil, in: .defaultClient, completionHandler: nil)
    }

    static func source(enabled: Bool, opacity: Double) -> String {
        let amount = opacity.isFinite ? min(1, max(0, opacity)) : 1
        return bootstrap + "\nwindow.__zigzagPageBackdrop?.set(\(enabled), \(amount));"
    }

    /// Only background-color is changed, never the opacity of a view or an element. Keeping a property-level
    /// journal preserves form values, images, foreground contrast, and a site's own changes made while enabled.
    /// The bounded scan handles full-page SPA shells without flattening cards, dialogs, or embedded frames.
    private static let bootstrap = #"""
    (() => {
      if (window.__zigzagPageBackdrop) return;
      let enabled = false, opacity = 1, timer = 0, observing = false;
      const edits = new Map();
      const supported = () => /^https?:$/.test(location.protocol)
        && /^(text\/html|application\/xhtml\+xml)$/.test(document.contentType)
        && !/\.pdf$/i.test(location.pathname);
      const restore = () => {
        for (const [node, saved] of edits) {
          if (node.style.getPropertyValue('background-color') !== saved.applied
              || node.style.getPropertyPriority('background-color') !== 'important') continue;
          if (saved.value) node.style.setProperty('background-color', saved.value, saved.priority);
          else node.style.removeProperty('background-color');
        }
        edits.clear();
      };
      const paint = (node, color) => {
        const saved = {value: node.style.getPropertyValue('background-color'),
          priority: node.style.getPropertyPriority('background-color')};
        // CSSOM property writes also work on sites whose CSP forbids injected inline stylesheets.
        node.style.setProperty('background-color', color, 'important');
        saved.applied = node.style.getPropertyValue('background-color');
        edits.set(node, saved);
      };
      const rgba = text => {
        if (!/^rgba?\(/.test(text)) return null;
        const n = text.match(/[\d.]+/g)?.map(Number);
        return n && n.length >= 3 ? [n[0], n[1], n[2], n[3] ?? 1] : null;
      };
      const colorOf = node => rgba(getComputedStyle(node).backgroundColor);
      const solid = color => color && color[3] > 0.05;
      const neutral = color => Math.max(...color.slice(0, 3)) - Math.min(...color.slice(0, 3)) < 42;
      const near = (a, b) => a.slice(0, 3).every((value, i) => Math.abs(value - b[i]) < 48);
      const observer = new MutationObserver(() => schedule());
      const observe = () => {
        if (!enabled || observing) return;
        observer.observe(document, {subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style']});
        observing = true;
      };
      const stopObserving = () => { observer.disconnect(); observing = false; };
      function apply() {
        stopObserving();
        restore();
        const root = document.documentElement, body = document.body;
        if (!enabled || !supported() || !root || !body) { observe(); return; }
        // At most 128 nodes and five container levels per update, no whole-page selector or pixel inspection.
        const shells = [], queue = Array.from(body.children).slice(0, 48).map(node => [node, 0]);
        const width = Math.max(1, innerWidth), height = Math.max(1, innerHeight);
        for (let visited = 0; queue.length && visited < 128; visited++) {
          const [node, depth] = queue.shift();
          if (!['DIV', 'MAIN', 'SECTION', 'ARTICLE'].includes(node.tagName)
              || node.matches('[role="dialog"], [role="alertdialog"], [popover]')) continue;
          const rect = node.getBoundingClientRect(), style = getComputedStyle(node);
          if (rect.width >= width * 0.85 && rect.height >= height * 0.75
              && style.position !== 'fixed' && style.position !== 'sticky'
              && style.backgroundImage === 'none') {
            const color = rgba(style.backgroundColor);
            if (solid(color)) shells.push([node, color]);
          }
          if (depth < 4) for (const child of Array.from(node.children).slice(0, 48)) {
            if (queue.length < 128) queue.push([child, depth + 1]);
          }
        }
        const bodyColor = colorOf(body), rootColor = colorOf(root);
        const canvas = solid(bodyColor) ? bodyColor : solid(rootColor) ? rootColor
          : shells[0]?.[1] ?? (matchMedia('(prefers-color-scheme: dark)').matches ? [28, 28, 30, 1] : [255, 255, 255, 1]);
        paint(root, `rgba(${canvas[0]}, ${canvas[1]}, ${canvas[2]}, ${canvas[3] * opacity})`);
        paint(body, 'transparent');
        for (const [node, color] of shells) if (neutral(color) && near(color, canvas)) paint(node, 'transparent');
        observe();
      }
      function schedule() {
        if (!enabled || timer) return;
        timer = setTimeout(() => { timer = 0; if (!document.hidden) apply(); }, 180);
      }
      const visibility = () => { if (!document.hidden) schedule(); };
      window.addEventListener('pagehide', () => { stopObserving(); clearTimeout(timer); timer = 0; });
      window.addEventListener('pageshow', () => { if (enabled) { observe(); schedule(); } });
      window.__zigzagPageBackdrop = {
        set(on, amount) {
          const wasEnabled = enabled;
          enabled = !!on && supported(); opacity = Math.max(0, Math.min(1, amount));
          clearTimeout(timer); timer = 0;
          if (enabled !== wasEnabled) {
            const method = enabled ? 'addEventListener' : 'removeEventListener';
            window[method]('resize', schedule);
            document[method]('load', schedule, true);
            document[method]('visibilitychange', visibility);
          }
          apply();
        }
      };
    })();
    """#
}
