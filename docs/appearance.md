# Browser appearance

Settings → Appearance (`zigzag://settings/appearance`) owns the window background and the existing borderless page,
large space names, favorites layout, and reduced motion settings. Ask before quitting remains in General.

New and existing profiles default to macOS frosted glass (`NSVisualEffectView`, behind-window blending), a soft
material, and 78% tint transparency. Soft, Balanced, and Dense select native materials; macOS controls their blur
kernel. Transparency changes the space-color wash above the material. Space Color restores the individual space's
color/gradient/glass behavior.

Wallpaper uses a local PNG copy in the profile, downsampled to at most 2560 pixels on its long edge. The original
file may move afterward. Opacity, blur, and shading are independent; expensive wallpaper blur is calculated once
on releasing its slider and cached across windows. Wallpaper fills the whole window with aspect-fill cropping.
Reset Appearance keeps the chosen image. Remove Wallpaper deletes only the app's imported copy and returns to
glass. System Reduce Transparency takes priority and uses the opaque space color.

## Web pages

Ordinary websites keep their authored, opaque canvas in Glass and Space Color modes. This avoids exposing the
window through a site's layout gutters or transparent table rows while neighboring content remains opaque.
Native Settings can still use the window material. With Wallpaper selected, Show wallpaper on web pages and
Web page background opacity control the page canvas. Text, images, videos,
form fields, and cards keep their opacity. The wallpaper itself stays in a native layer: its file path and image
bytes never enter the website. Normal navigation, split panes, returning tabs, and Peek promotion reapply the
current appearance. Settings uses its native translucent surface with its placeholder web view hidden.

The bridge changes HTML/body background colors and matching neutral containers occupying most of the viewport.
It does not remove authored background images, fixed overlays, dialogs, PDF pages, extension pages, local files,
or canvas/video content. Such content may remain opaque. Disabling the effect restores the authored background
properties, including changes a site made while it was enabled. A bounded, throttled observer follows SPA shells.

macOS WebKit has no public canvas-transparency switch. The bridge checks for the optional background setter
already used by Peek and falls back to an opaque canvas if it disappears. The installed WebKit was checked with
a real WKWebView: its setter clears and restores the canvas, and underPageBackgroundColor accepts transparent.
The behavior tests use fabricated HTML in a nonpersistent WKWebView; they are not a claim about every live site.

## Validation

Automated coverage includes preference defaults/persistence/range checks, settings URL restoration, shared
selection movement, native WebKit page backgrounds and SPA updates, foreground/form preservation, and restoration.

For visual acceptance on a real desktop:

- Switch macOS between light/dark and Reduce Transparency; inspect an active and inactive window.
- Choose a wallpaper, change each slider, resize the window, hide the sidebar, and use a split view.
- Open Settings → Appearance; confirm the image shows behind the native settings page too.
- Browse a light page and a dark SPA, toggle page backgrounds, and verify text and login fields remain readable.
- Click settings categories rapidly, resize to the compact rail, and enable Reduce Motion. Only the highlight
  travels; category text and icons retain their size. Password categories and segmented filters use the same rule.

Native password support and its separate runtime limits are described in [password-native-autofill.md](password-native-autofill.md).
