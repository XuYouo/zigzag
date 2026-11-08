import AppKit
import CoreImage
import ImageIO

/// Global appearance, shared by existing windows and tabs as well as new ones.
enum BrowserAppearance {
    enum Background: String, CaseIterable {
        case glass, wallpaper, space
        var title: String {
            switch self {
            case .glass: String(localized: "Native Frosted Glass")
            case .wallpaper: String(localized: "Wallpaper")
            case .space: String(localized: "Space Color")
            }
        }
    }
    enum Material: String, CaseIterable {
        case sidebar, underWindow, hud
        var title: String {
            switch self {
            case .sidebar: String(localized: "Soft")
            case .underWindow: String(localized: "Balanced")
            case .hud: String(localized: "Dense")
            }
        }
        var value: NSVisualEffectView.Material {
            switch self { case .sidebar: .sidebar; case .underWindow: .underWindowBackground; case .hud: .hudWindow }
        }
    }
    static let changed = Signal<Void>()
    private static let defaults = UserDefaults.standard
    static var background: Background {
        get { Background(rawValue: defaults.string(forKey: "Appearance.background") ?? "") ?? .glass }
        set { defaults.set(newValue.rawValue, forKey: "Appearance.background"); changed.send() }
    }
    static var material: Material {
        get { Material(rawValue: defaults.string(forKey: "Appearance.material") ?? "") ?? .sidebar }
        set { defaults.set(newValue.rawValue, forKey: "Appearance.material"); changed.send() }
    }
    static func amount(_ key: String, fallback: Double) -> Double {
        let value = defaults.object(forKey: "Appearance." + key) as? Double ?? fallback
        return value.isFinite ? min(1, max(0, value)) : fallback
    }
    static func setAmount(_ value: Double, key: String) {
        guard value.isFinite else { return }
        defaults.set(min(1, max(0, value)), forKey: "Appearance." + key)
        changed.send()
    }
    static var transparency: Double { amount("transparency", fallback: 0.78) }
    static var wallpaperOpacity: Double { amount("wallpaperOpacity", fallback: 0.85) }
    static var wallpaperBlur: Double { amount("wallpaperBlur", fallback: 0.15) }
    static var wallpaperShade: Double { amount("wallpaperShade", fallback: 0.18) }
    static var pageOpacity: Double { amount("pageOpacity", fallback: 0.82) }
    static var onWebsites: Bool {
        get { defaults.object(forKey: "Appearance.onWebsites") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "Appearance.onWebsites"); changed.send() }
    }
    static var reducesTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    /// Native pages may use the window material. Websites retain their authored canvas in glass/color mode;
    /// only an explicitly selected wallpaper can show through a website's background.
    static var translucentSurfaces: Bool { background != .space && !reducesTransparency && pageOpacity < 1 }
    static var translucentPages: Bool { background == .wallpaper && onWebsites && translucentSurfaces }
    static var surfaceColor: NSColor {
        Tokens.Color.surface.withAlphaComponent(translucentSurfaces ? pageOpacity : 1)
    }
    static var wallpaperName: String? { defaults.string(forKey: "Appearance.wallpaperName") }
    private static var imageURL: URL { Paths.file("AppearanceWallpaper.png") }
    private static var imageCache: CGImage?
    private static var loaded = false
    private static var rendered: (Double, CGImage)?
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Decode a bounded thumbnail, then copy it into the profile. The chosen original can move or disappear.
    static func importWallpaper(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try data.write(to: imageURL, options: .atomic)
        imageCache = image; loaded = true; rendered = nil
        defaults.set(url.lastPathComponent, forKey: "Appearance.wallpaperName")
        background = .wallpaper
    }
    static func removeWallpaper() throws {
        if FileManager.default.fileExists(atPath: imageURL.path) { try FileManager.default.removeItem(at: imageURL) }
        imageCache = nil; loaded = true; rendered = nil
        defaults.removeObject(forKey: "Appearance.wallpaperName")
        background = .glass
    }
    static func wallpaperImage() -> CGImage? {
        if !loaded {
            loaded = true
            if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
                imageCache = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2560] as CFDictionary)
            }
        }
        guard let image = imageCache else { return nil }
        let blur = wallpaperBlur * 40
        if let rendered, rendered.0 == blur { return rendered.1 }
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur]).cropped(to: input.extent)
        let result = context.createCGImage(output, from: input.extent) ?? image
        rendered = (blur, result)
        return result
    }
}

/// A wallpaper is a native layer, never sent to a website or injected as a file URL.
final class WallpaperBackdrop: NSView {
    private let picture = CALayer()
    private let shade = CALayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        picture.contentsGravity = .resizeAspectFill
        layer?.addSublayer(picture)
        layer?.addSublayer(shade)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func refresh() {
        isHidden = BrowserAppearance.background != .wallpaper || BrowserAppearance.reducesTransparency
        guard !isHidden else { return }
        Tokens.Motion.withoutAnimation {
            picture.contents = BrowserAppearance.wallpaperImage()
            picture.opacity = Float(BrowserAppearance.wallpaperOpacity)
            shade.backgroundColor = cgColor(Tokens.Color.surface.withAlphaComponent(BrowserAppearance.wallpaperShade))
        }
    }
    override func layout() {
        super.layout()
        Tokens.Motion.withoutAnimation { picture.frame = bounds; shade.frame = bounds }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
}
