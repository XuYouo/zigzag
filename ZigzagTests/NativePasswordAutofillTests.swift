import AppKit
import JavaScriptCore
import Testing
@testable import Zigzag

@MainActor
struct NativePasswordAutofillTests {
    @Test func requiresSelectedHTTPSMainFrameAndExactOrigin() throws {
        let origin = try #require(Origin(URL(string: "https://accounts.example.com/sign-in")))
        func allowed(_ url: String?, main: Bool = true, selected: Bool = true) -> Bool {
            NativePasswordAutofill.canFill(original: origin, currentURL: url.flatMap(URL.init(string:)), isMainFrame: main, isSelected: selected)
        }
        #expect(allowed("https://accounts.example.com/sign-in"))
        #expect(!allowed("https://evil.example.com/sign-in"))
        #expect(!allowed("https://accounts.example.com:8443/sign-in"))
        #expect(!allowed("http://accounts.example.com/sign-in"))
        #expect(!allowed(nil))
        #expect(!allowed("https://accounts.example.com", main: false))
        #expect(!allowed("https://accounts.example.com", selected: false))
        let insecure = try #require(Origin(URL(string: "http://example.com")))
        #expect(!NativePasswordAutofill.canFill(original: insecure, currentURL: URL(string: "http://example.com"), isMainFrame: true, isSelected: true))
    }

    @Test func nativeEditorsUseSystemContentTypes() {
        let secure = FilledField(placeholder: "Password", secure: true)
        #expect(secure.field is NSSecureTextField)
        #expect(secure.field.contentType == .password)
        #expect(FilledField.search("Search").field.contentType == nil)
    }

    private func context() -> JSContext {
        let context = JSContext()!
        context.exceptionHandler = { _, error in Issue.record("JavaScript exception: \(error?.toString() ?? "unknown")") }
        context.evaluateScript("""
        var window = globalThis, innerWidth = 800, innerHeight = 600;
        var location = { protocol: 'https:', origin: 'https://example.com', href: 'https://example.com/login' };
        var getComputedStyle = () => ({ visibility: 'visible', opacity: '1' });
        var setTimeout = f => f();
        var Event = class {}, InputEvent = class {};
        var HTMLInputElement = class {
          constructor(type, y) { this.type = type; this.y = y; this.tagName = 'INPUT'; this.isConnected = true; this.value = ''; this.events = 0; }
          get value() { return this._value; }
          set value(value) { this._value = value; }
          getBoundingClientRect() { return { left: 20, right: 220, top: this.y, bottom: this.y + 30, width: 200, height: 30 }; }
          checkVisibility() { return !this.hidden; }
          dispatchEvent() { this.events++; }
        };
        var user = new HTMLInputElement('text', 20), pass = new HTMLInputElement('password', 80);
        user.autocomplete = 'username'; pass.autocomplete = 'current-password';
        var form = { querySelectorAll: () => [user, pass] };
        user.form = form; pass.form = form;
        var document = { activeElement: user, elementFromPoint: (x, y) => y < 70 ? user : pass };
        var token = 'request-one', expectedOrigin = 'https://example.com', username = 'tester', password = 'synthetic-secret';
        """)
        context.setObject(NativePasswordAutofill.prepare, forKeyedSubscript: "prepareSource" as NSString)
        context.setObject(NativePasswordAutofill.fill, forKeyedSubscript: "fillSource" as NSString)
        return context
    }

    @Test func fillsOnlyPinnedFieldsAndConsumesRequestOnce() {
        let context = context()
        #expect(context.evaluateScript("new Function(prepareSource)()")?.toBool() == true)
        #expect(context.evaluateScript("new Function(fillSource)()")?.toBool() == true)
        #expect(context.evaluateScript("user.value")?.toString() == "tester")
        #expect(context.evaluateScript("pass.value")?.toString() == "synthetic-secret")
        #expect(context.evaluateScript("pass.events")?.toInt32() == 2)
        #expect(context.evaluateScript("new Function(fillSource)()")?.toBool() == false)
    }

    @Test func staleDocumentOrChangedFieldsNeverReceivePassword() {
        for change in [
            "location.origin = 'https://other.example'",
            "location.href = 'https://example.com/changed'",
            "delete window.__zigzagNativePasswordTarget", // a new document, even at the same URL
            "token = 'another-request'",
            "pass.isConnected = false",
            "pass.hidden = true",
            "pass.type = 'text'",
            "pass.form = {}",
            "pass.autocomplete = 'new-password'"
        ] {
            let context = context()
            #expect(context.evaluateScript("new Function(prepareSource)()")?.toBool() == true)
            context.evaluateScript(change)
            #expect(context.evaluateScript("new Function(fillSource)()")?.toBool() == false, "Rejected: \(change)")
            #expect(context.evaluateScript("pass.value")?.toString() == "")
            #expect(context.evaluateScript("user.value")?.toString() == "")
        }
    }
}
