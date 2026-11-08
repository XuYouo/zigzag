import AppKit
import UniformTypeIdentifiers

/// Appearance controls use the same sliders and rows as the space editor.
final class AppearanceSettings {
    let group = FormGroup()
    private let background = DropdownButton()
    private let material = DropdownButton()
    private let websites = Toggle()
    private let imageName = Label("", font: Tokens.Font.detail(), color: Tokens.Color.textSecondary)
    private let remove = PillButton(title: String(localized: "Remove Wallpaper"))
    private var sliders: [(AppearanceAmount, () -> Double)] = []
    private var token: SignalToken?
    private weak var host: NSView?

    func build(in host: NSView) {
        self.host = host
        imageName.translatesAutoresizingMaskIntoConstraints = false
        imageName.widthAnchor.constraint(equalToConstant: 200).isActive = true
        imageName.lineBreakMode = .byTruncatingMiddle
        background.options = BrowserAppearance.Background.allCases.map { .init(title: $0.title) }
        background.onSelect = { BrowserAppearance.background = BrowserAppearance.Background.allCases[$0] }
        group.add(FormRow(title: String(localized: "Window background"), control: background))
        material.options = BrowserAppearance.Material.allCases.map { .init(title: $0.title) }
        material.onSelect = { BrowserAppearance.material = BrowserAppearance.Material.allCases[$0] }
        group.add(FormRow(title: String(localized: "Glass material"),
                          detail: String(localized: "macOS blurs the desktop behind the window. Materials change its density."), control: material))
        addAmount(String(localized: "Glass transparency"), key: "transparency", read: { BrowserAppearance.transparency })

        let choose = PillButton(title: String(localized: "Choose Image…"))
        choose.onClick = { [weak self] _ in self?.chooseWallpaper() }
        remove.onClick = { [weak self] _ in
            do { try BrowserAppearance.removeWallpaper() }
            catch { self?.showError(error) }
        }
        let buttons = NSStackView(views: [choose, remove])
        buttons.spacing = Tokens.Space.x2
        group.add(FormRow(title: String(localized: "Wallpaper image"),
                          detail: String(localized: "A local copy fills the window and stays available if the original moves."), control: buttons))
        group.add(FormRow(title: String(localized: "Selected image"), control: imageName))
        addAmount(String(localized: "Wallpaper opacity"), key: "wallpaperOpacity", read: { BrowserAppearance.wallpaperOpacity })
        addAmount(String(localized: "Wallpaper blur"), key: "wallpaperBlur", read: { BrowserAppearance.wallpaperBlur }, onRelease: true)
        addAmount(String(localized: "Wallpaper shading"), key: "wallpaperShade", read: { BrowserAppearance.wallpaperShade })
        websites.onChange = { BrowserAppearance.onWebsites = $0 }
        group.add(FormRow(title: String(localized: "Show wallpaper on web pages"),
                          detail: String(localized: "Applies when Wallpaper is selected. Glass and Space Color keep websites’ original backgrounds. Some sites draw their own opaque content."), control: websites))
        addAmount(String(localized: "Web page background opacity"), key: "pageOpacity", read: { BrowserAppearance.pageOpacity })
        let reset = PillButton(title: String(localized: "Reset Appearance"))
        reset.onClick = { _ in
            BrowserAppearance.background = .glass
            BrowserAppearance.material = .sidebar
            for (key, value) in [("transparency", 0.78), ("wallpaperOpacity", 0.85), ("wallpaperBlur", 0.15), ("wallpaperShade", 0.18), ("pageOpacity", 0.82)] {
                BrowserAppearance.setAmount(value, key: key)
            }
            BrowserAppearance.onWebsites = true
        }
        group.add(FormRow(title: String(localized: "Default appearance"),
                          detail: String(localized: "Restore the glass and wallpaper effects. Your chosen image is kept. macOS Reduce Transparency takes priority."), control: reset))
        token = BrowserAppearance.changed.observe { [weak self] in self?.refresh() }
        refresh()
    }
    private func addAmount(_ title: String, key: String, read: @escaping () -> Double, onRelease: Bool = false) {
        let slider = AppearanceAmount(title: title)
        slider.onChange = { value, final in
            if !onRelease || final { BrowserAppearance.setAmount(value, key: key) }
        }
        sliders.append((slider, read))
        group.add(FormRow(title: title, control: slider))
    }
    private func refresh() {
        background.selectedIndex = BrowserAppearance.Background.allCases.firstIndex(of: BrowserAppearance.background) ?? 0
        material.selectedIndex = BrowserAppearance.Material.allCases.firstIndex(of: BrowserAppearance.material) ?? 0
        websites.isOn = BrowserAppearance.onWebsites
        imageName.stringValue = BrowserAppearance.wallpaperName ?? String(localized: "No image selected")
        imageName.toolTip = BrowserAppearance.wallpaperName
        imageName.invalidateIntrinsicContentSize()
        remove.isEnabled = BrowserAppearance.wallpaperName != nil
        sliders.forEach { $0.0.value = $0.1() }
        group.needsLayout = true
    }
    private func chooseWallpaper() {
        guard let window = host?.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try BrowserAppearance.importWallpaper(url) }
            catch { self?.showError(error) }
        }
    }
    private func showError(_ error: Error) {
        guard let host else { return }
        ConfirmSheet.notice(in: host, title: String(localized: "Couldn’t update the wallpaper"), message: error.localizedDescription)
    }
}

private final class AppearanceAmount: NSView {
    private let slider = LookSlider(.amount)
    private let number = Label("", font: Tokens.Font.detail(), color: Tokens.Color.textSecondary)
    var onChange: ((Double, Bool) -> Void)?
    var value: Double {
        get { slider.value }
        set { slider.value = newValue; updateNumber() }
    }
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: Tokens.Page.controlHeight))
        slider.setAccessibilityLabel(title)
        addSubview(slider); addSubview(number)
        slider.onChange = { [weak self] value, final in
            self?.updateNumber()
            self?.onChange?(value, final)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: Tokens.Page.controlHeight) }
    private func updateNumber() { number.stringValue = value.formatted(.percent.precision(.fractionLength(0))) }
    override func layout() {
        super.layout()
        slider.frame = NSRect(x: 0, y: 0, width: bounds.width - 46, height: bounds.height)
        number.frame = NSRect(x: bounds.width - 42, y: (bounds.height - number.lineHeight) / 2, width: 42, height: number.lineHeight)
    }
}
