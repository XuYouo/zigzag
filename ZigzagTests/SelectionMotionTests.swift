import AppKit
import Testing
@testable import Zigzag

@MainActor
struct SelectionMotionTests {
    @Test func navigationPressKeepsItsSize() {
        let item = ListItem(title: "Appearance", symbol: "paintpalette")
        item.frame = NSRect(x: 0, y: 0, width: 200, height: 34)
        item.isPressed = true
        #expect(!item.pressScales)
        #expect(item.layer?.animation(forKey: "press") == nil)
        #expect(CATransform3DEqualToTransform(item.layer!.transform, CATransform3DIdentity))
        item.isPressed = false
        #expect(item.layer?.animation(forKey: "press") == nil)
    }

    @Test func sharedNavigationNeverPaintsASecondBlockDuringClick() {
        let row = ListItem(title: "Appearance", symbol: "paintpalette")
        row.drawsSelection = false
        // The real pointer sequence: hover, mouse down, release, then the onClick changes selection.
        for state in [(true, false, false), (true, true, false), (true, false, false), (true, false, true), (false, false, false)] {
            row.isHovered = state.0
            row.isPressed = state.1
            row.isSelected = state.2
            #expect((row.layer?.backgroundColor?.alpha ?? 0) == 0)
            #expect(row.layer?.animation(forKey: "backgroundColor") == nil)
        }
        // Ordinary lists still own their own hover/press/selection feedback.
        row.drawsSelection = true
        row.isHovered = true
        #expect((row.layer?.backgroundColor?.alpha ?? 0) > 0)
    }

    @Test func segmentedFiltersNeverPaintASecondBlockDuringClick() {
        let filters = SegmentedPills(["All", "Weak", "Reused"])
        let items = filters.subviews.compactMap { $0 as? InteractiveView }
        #expect(items.count == 3)
        for item in items {
            item.isHovered = true
            item.isPressed = true
            #expect((item.layer?.backgroundColor?.alpha ?? 0) == 0)
            item.isPressed = false
            item.isSelected = true
            #expect((item.layer?.backgroundColor?.alpha ?? 0) == 0)
            #expect(item.layer?.animation(forKey: "backgroundColor") == nil)
        }
    }

    @Test func relayoutKeepsSelectionTravelingToItsDestination() {
        let selection = SelectionGlide()
        selection.move(to: NSRect(x: 0, y: 0, width: 120, height: 34), animated: false)
        let destination = NSRect(x: 0, y: 72, width: 180, height: 34)
        selection.move(to: destination, animated: true)
        #expect(selection.frame == destination)
        let moves = !Tokens.Motion.reduceMotion && !Tokens.Motion.isFromKey
        #expect((selection.layer?.animation(forKey: "glide") != nil) == moves)
        // AppKit lays the column out again after changing the pane's content. It must not cancel the travel.
        selection.move(to: destination, animated: false)
        #expect((selection.layer?.animation(forKey: "glide") != nil) == moves)
        selection.move(to: .zero, animated: false)
        #expect(selection.isHidden)
        #expect(selection.layer?.animation(forKey: "glide") == nil)
    }
}

/// Real AppKit windows, kept off screen: same-document changes must not reposition native window controls.
@MainActor
struct WindowChromeMotionTests {
    @Test func changingSettingsAddressesLeavesTheWholeToolbarStill() async throws {
        let window = makeWindow()
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 820))
        window.contentView!.addSubview(sidebar)
        window.updatePageIdentity(title: "Settings", url: SettingsPage.url)
        sidebar.trafficLightsWidth = window.trafficLightsWidth
        window.contentView!.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        let controls = buttons(in: window) + [sidebar.sidebarButton]
        let frames = controls.map { $0.convert($0.bounds, to: nil) }
        let changes = FrameChanges(window: window, views: controls)
        defer { changes.stop(); window.close() }
        for _ in 0..<3 {
            for pane in SettingsPane.allCases {
                window.updatePageIdentity(title: "Settings", url: SettingsPage.url(for: pane))
                // The regular layout callback still runs; a stationary toolbar should not depend on skipping it.
                window.layoutTrafficLights()
                sidebar.trafficLightsWidth = window.trafficLightsWidth
                sidebar.needsLayout = true
                window.contentView!.layoutSubtreeIfNeeded()
                await Task.yield()
                #expect(window.accessibilityDocument() == SettingsPage.url(for: pane).absoluteString)
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(changes.widths.isEmpty)
        #expect(controls.map { $0.convert($0.bounds, to: nil) } == frames)
        #expect(window.title == "Settings")
    }

    @Test func nativeTitlebarRelayoutCannotChangeTheSidebarButtonsReservedSpace() async throws {
        let window = makeWindow()
        window.updatePageIdentity(title: "First page", url: URL(string: "https://example.com/first"))
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let width = window.trafficLightsWidth
        let changes = FrameChanges(window: window, views: buttons(in: window))
        defer { changes.stop(); window.close() }

        // AppKit moves the lights one at a time when the title really changes. Their reserved width must not
        // briefly grow or shrink while only some of them have returned to the browser's custom positions.
        window.representedURL = URL(fileURLWithPath: "/tmp/zigzag-window-chrome-fixture.pdf")
        let address = URL(string: "https://example.com/second")!
        window.updatePageIdentity(title: "Second page", url: address)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!changes.widths.isEmpty)
        #expect(changes.widths.allSatisfy { $0 == width })
        #expect(window.trafficLightsWidth == width)
        #expect(window.title == "Second page")
        #expect(window.representedURL == nil)
        #expect(window.accessibilityDocument() == address.absoluteString)

        // A cleared tab also clears its accessibility address, without disturbing the native controls.
        window.updatePageIdentity(title: "Zigzag", url: nil)
        #expect(window.accessibilityDocument() == nil)

        // Real geometry changes still work, including a different origin for a floating sidebar.
        window.setContentSize(NSSize(width: 1000, height: 650))
        let origin = NSPoint(x: 20, y: 25)
        window.trafficLightOrigin = origin
        let close = try #require(window.standardWindowButton(.closeButton))
        let frame = close.convert(close.bounds, to: nil)
        #expect(frame.minX == origin.x)
        #expect(frame.maxY == window.contentView!.frame.height - origin.y)
        #expect(window.trafficLightsWidth == width)
    }

    private func makeWindow() -> BrowserWindow {
        let bounds = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let window = BrowserWindow(contentRect: bounds)
        window.contentView = NSView(frame: bounds)
        window.trafficLightOrigin = NSPoint(x: SidebarView.trafficLightsX,
                                           y: Tokens.Sidebar.lightsCenter - window.trafficLightHeight / 2)
        return window
    }

    private func buttons(in window: BrowserWindow) -> [NSView] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
    }

    @MainActor private final class FrameChanges {
        var widths: [CGFloat] = []
        private var tokens: [NSObjectProtocol] = []
        private weak var window: BrowserWindow?

        init(window: BrowserWindow, views: [NSView]) {
            self.window = window
            for view in views {
                view.postsFrameChangedNotifications = true
                tokens.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                                    object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if let self, let window = self.window { self.widths.append(window.trafficLightsWidth) }
                    }
                })
            }
        }

        func stop() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
        }
    }
}
