# Native password entry

Zigzag enables macOS Password AutoFill on its native username and secure password fields using the public AppKit `contentType` API. Password editing uses `NSSecureTextField` rather than a plain text editor. HTTP authentication sheets identify their username field as `.username`; secure fields identify themselves as `.password`.

On an HTTPS website, the existing password suggestion menu includes **Use macOS Passwords…**. This opens a sheet with native username/password fields and names the destination website. The user selects or enters a login and clicks **Fill**. Filling does not submit the website's form and does not import the login into Zigzag's vault.

## What the platform supports

- Apple's [AutoFill everywhere, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10115/) demonstrates AppKit username/password AutoFill at 9:20 using `NSTextField.contentType = .username` and `NSSecureTextField.contentType = .password`.
- [`NSTextContent.contentType`](https://developer.apple.com/documentation/appkit/nstextcontent/contenttype) describes field semantics to the system; it does not provide access to the Passwords database or set an arbitrary website association.
- [Shared Web Credentials](https://developer.apple.com/documentation/security/shared-web-credentials) requires authorization from the app, website, and user. A general browser cannot declare an association with every website it visits.
- [Passkey use in web browsers](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers) is a separate integration. The existing code checks the browser passkey entitlement; this change neither adds nor bypasses that entitlement.

This is native AutoFill-enabled input, not a public replacement for Safari's website password suggestion interface. The OS and the user's enabled credential provider control whether and how a picker appears. No API in the installed SDK was found to enable Safari's complete password integration for arbitrary websites in a macOS `WKWebView`. AppKit annotations alone do not guarantee a domain-matched suggestion for an unassociated application. The user must select the intended login and check the destination. There is no private API, vault scraping, clipboard-based transfer, or automatic form submission.

## Security boundaries

The bridge accepts only the selected main-frame HTTPS page with the original exact origin. Before showing the sheet it binds the original visible form fields, document URL, and a one-use request token in WebKit's isolated client world. Before filling it checks the tab, origin, document, field identity, form membership, visibility, editability, and password field type again. A reload, navigation, disconnected/replaced field, or changed form rejects the result. Password values are JavaScript arguments, never script source or logs. The sheet clears its detached native editors on completion or cancellation.

The original field is captured before the native sheet takes keyboard focus. Closing the sheet restores the web view as first responder, but filling uses the captured field identities rather than whichever element subsequently becomes `document.activeElement`. The password menu's click handler does not itself take first responder. These are code-path checks; actual AppKit/WebKit focus behavior still requires the manual checks below.

## Verification

`NativePasswordAutofillTests` covers native secure-field types, the HTTPS/main-frame/current-tab/exact-origin gate, and the JavaScript bridge using a synthetic DOM in JavaScriptCore. It covers one-use tokens, changed origins and document URLs, simulated reloads, hidden/disconnected fields, changed field types, new-password fields, and changed forms. These tests do **not** verify an OS password picker or real website focus behavior.

No GUI or personal password vault was accessed during implementation. Test the signed app on each supported macOS version with a synthetic login:

1. Enable the desired password provider in System Settings > AutoFill & Passwords and save a throwaway account for an HTTPS test site.
2. Focus the site's username or current-password field, choose **Use macOS Passwords…**, and focus the native password field. Confirm the system's picker/AutoFill action is offered, including when Zigzag has no associated domain for that website. Confirm its authentication prompt remains usable.
3. Select the throwaway login, verify the destination shown in the sheet, and click **Fill**. Both webpage fields should receive their values and the form should remain unsubmitted. Test mouse and keyboard selection, cancellation, and a username-first sign-in flow.
4. While the sheet is open, reload or navigate the page, replace/hide its form, switch tabs, or close the window. Confirm no password is filled into a new or hidden document.
5. Repeat in private browsing, with system AutoFill disabled, and with an alternative credential provider. Provider-disabled cases must leave ordinary secure text entry usable and must not claim that a picker is available.
6. Check native HTTP authentication and the saved-password editor. Password edits stay masked; explicit reveal/copy actions outside editing keep their existing authentication behavior.

If the native picker is not offered for an unassociated app on a particular OS/provider configuration, the secure fields still work manually. That configuration must be reported as lacking system picker integration; passing unit tests is not evidence that it works there.
