import AppKit
import WebKit

/// AppKit owns the Password AutoFill picker and secure editor. The user explicitly transfers its result to a
/// website; this does not grant Zigzag access to the Passwords database or impersonate an associated domain.
enum NativePasswordAutofill {
    static func canFill(original: Origin, currentURL: URL?, isMainFrame: Bool, isSelected: Bool) -> Bool {
        isMainFrame && isSelected && original.scheme == "https" && Origin(currentURL) == original
    }

    static func show(in webView: BrowserWebView, frame: WKFrameInfo, origin: Origin) {
        let isCurrent = {
            canFill(original: origin, currentURL: webView.url, isMainFrame: frame.isMainFrame,
                    isSelected: WindowManager.shared.controllers.first(where: { $0.window === webView.window })?.selectedWebView === webView)
        }
        guard isCurrent(), let window = webView.window else { return }
        Task { @MainActor in
            let token = UUID().uuidString
            let arguments: [String: Any] = ["token": token, "expectedOrigin": origin.description]
            guard (try? await webView.callAsyncJavaScript(prepare, arguments: arguments, in: frame, contentWorld: .defaultClient)) as? Bool == true,
                  isCurrent() else { return }
            let result = await PageDialogSheet.ask(
                in: window,
                title: String(localized: "Fill password for \(origin.description)", comment: "Title of the native password fill sheet; the placeholder is the exact HTTPS origin, including any nondefault port."),
                message: String(localized: "Choose a login using macOS Password AutoFill in the fields below, then click Fill. Check that the login belongs to this website.", comment: "Explains the system password picker in the native password fill sheet."),
                fields: [.init(placeholder: String(localized: "Username"), contentType: .username),
                         .init(placeholder: String(localized: "Password"), secure: true, contentType: .password)],
                confirmTitle: String(localized: "Fill", comment: "Fill credentials into the website without submitting the form."),
                showsCancel: true, offersBlock: false, page: webView)
            defer {
                // Clear only this request. A second invocation must keep its own field binding.
                webView.callAsyncJavaScript(cleanup, arguments: ["token": token], in: frame, in: .defaultClient, completionHandler: nil)
            }
            guard case .confirmed(let values) = result, values.count == 2, isCurrent() else { return }
            let secret = SecretString(values[1])
            let fillArguments: [String: Any] = ["token": token, "expectedOrigin": origin.description,
                                                "username": values[0], "password": secret.withUnsafeString { $0 }]
            let filled = (try? await webView.callAsyncJavaScript(fill, arguments: fillArguments, in: frame, contentWorld: .defaultClient)) as? Bool == true
            if !filled, let controller = WindowManager.shared.controllers.first(where: { $0.window === webView.window }) {
                Toast.show(String(localized: "The sign-in form changed. Select the field and try again.", comment: "Native password fill was cancelled because the original form changed."),
                           symbol: "exclamationmark.triangle", duration: 4, in: controller)
            }
        }
    }

    // These scripts run in WebKit's isolated client world. Bind the exact fields before displaying any secret,
    // so a navigation, reload, hidden field, or replacement form cannot receive the eventual result.
    private static let visible = """
    const visible = (el) => {
      if (!el || !el.isConnected || el.disabled || el.readOnly || el.type === 'hidden') return false;
      const r = el.getBoundingClientRect();
      if (r.width < 8 || r.height < 8 || r.bottom <= 0 || r.top >= innerHeight || r.right <= 0 || r.left >= innerWidth) return false;
      if (el.checkVisibility && !el.checkVisibility({ opacityProperty: true, visibilityProperty: true })) return false;
      const style = getComputedStyle(el);
      if (style.visibility !== 'visible' || parseFloat(style.opacity) < 0.1) return false;
      const x = Math.max(0, Math.min(innerWidth - 1, r.left + r.width / 2));
      const y = Math.max(0, Math.min(innerHeight - 1, r.top + r.height / 2));
      return document.elementFromPoint(x, y) === el;
    };
    """

    static let prepare = visible + """
    if (location.protocol !== 'https:' || location.origin !== expectedOrigin) return false;
    const active = document.activeElement;
    if (!visible(active) || active.tagName !== 'INPUT') return false;
    const scope = active.form || document;
    const inputs = [...scope.querySelectorAll('input')].filter(visible);
    const passwordField = inputs.find(el => el.type === 'password' && !/new-password/.test(el.autocomplete || ''));
    const userFields = inputs.filter(el => ['text', 'email', 'tel', ''].includes(el.type));
    const usernameField = userFields.includes(active) ? active :
      userFields.find(el => /username|email/.test(el.autocomplete || '')) ||
      (passwordField ? userFields.filter(el => inputs.indexOf(el) < inputs.indexOf(passwordField)).pop() : null);
    if (!passwordField && !usernameField) return false;
    window.__zigzagNativePasswordTarget = { token, url: location.href, usernameField, passwordField, scope };
    return true;
    """

    static let fill = visible + """
    const target = window.__zigzagNativePasswordTarget;
    if (!target || target.token !== token) return false;
    delete window.__zigzagNativePasswordTarget;
    if (location.protocol !== 'https:' || location.origin !== expectedOrigin || location.href !== target.url) return false;
    const user = target.usernameField, pass = target.passwordField;
    const valid = () => (!user || (visible(user) && ['text', 'email', 'tel', ''].includes(user.type) && (user.form || document) === target.scope)) &&
      (!pass || (visible(pass) && pass.type === 'password' && !/new-password/.test(pass.autocomplete || '') && (pass.form || document) === target.scope));
    if (!valid() || (pass && !password) || (!pass && !username)) return false;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    window.__zigzagFilling = true;
    try {
      // Assign both before dispatching events; page handlers cannot swap the second field in between.
      if (user && username) setter.call(user, username);
      if (pass) setter.call(pass, password);
      for (const el of [user && username ? user : null, pass].filter(Boolean)) {
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertReplacementText' }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
    } finally { setTimeout(() => { window.__zigzagFilling = false; }, 0); }
    return true;
    """

    static let cleanup = """
    if (window.__zigzagNativePasswordTarget?.token === token) delete window.__zigzagNativePasswordTarget;
    """
}
