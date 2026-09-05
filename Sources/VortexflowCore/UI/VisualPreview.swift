#if DEBUG
import AppKit
import SwiftUI

/// A local-only rendering harness. Uses the real overlay, synthetic windows and
/// a controlled window behind it; never installs input taps or writes settings.
@MainActor
public enum VisualPreview {
    public static var isRequested: Bool {
        CommandLine.arguments.contains("--visual-preview")
            || Bundle.main.object(forInfoDictionaryKey: "VortexflowVisualPreview") as? Bool == true
    }

    public static func run() {
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class PreviewModel: ObservableObject {
    let state = OverlayState()
    @Published var dark = true { didSet { onAppearance?(dark) } }
    @Published var textured = false
    @Published var invertBackdrop = false
    @Published var opaque = false
    @Published var motion = true {
        didSet { state.reduceMotion = !motion }
    }
    var onAppearance: ((Bool) -> Void)?

    init() {
        let assets = Bundle.main.resourceURL?.appendingPathComponent("PreviewIcons").path ?? ""
        let examples = [
            ("Figma", "figma.png"), ("Google Chrome", "chrome.png"),
            ("Google Chrome", "chrome.png"), ("Claude", "claude.png"),
            ("Slack", "slack.png"), ("Grok", "grok.png"),
            ("Google Chrome", "chrome.png"), ("ChatGPT", "chatgpt.png"),
            ("Linear", "linear.png"), ("Brave", "brave.png"),
            ("Terminal", "terminal.png"), ("Finder", "finder-native.png"),
            ("Safari", "safari-native.png"), ("Cursor", "cursor.png"),
        ]
        state.layoutStyle = .spiral
        state.viewMode = .icon
        state.availableContentWidth = 1100
        state.availableContentHeight = 950
        state.load(entries: examples.enumerated().map { index, example in
            WindowEntry(windowID: CGWindowID(90_000 + index), processID: pid_t(90_000 + index),
                applicationName: example.0,
                applicationIcon: NSImage(contentsOfFile: assets + "/" + example.1),
                title: index == 2 ? "Project Northstar — launch plan" : example.0,
                frame: CGRect(x: 0, y: 0, width: 900, height: 650),
                isMinimized: false, zOrder: index, axElement: nil)
        }, selectedIndex: 2)
        state.isVisible = true
    }

    func selectNext() {
        state.setSelection(((state.selectedIndex ?? 0) + 1) % state.entries.count)
    }
}

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    let model = PreviewModel()
    var backdrop: NSWindow?
    var controls: NSWindow?
    var overlay: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit visual preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; main.addItem(root); NSApp.mainMenu = main

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = CGSize(width: min(1160, visible.width - 60), height: min(1000, visible.height - 130))
        model.state.availableContentWidth = size.width - 30
        model.state.availableContentHeight = size.height - 30
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 25)

        let background = NSWindow(contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        background.title = "VortexFlow preview backdrop"
        background.isReleasedWhenClosed = false
        background.contentView = NSHostingView(rootView: PreviewBackdrop(model: model))
        background.orderFrontRegardless()
        backdrop = background

        let controlWindow = NSWindow(contentRect: CGRect(origin: origin,
            size: CGSize(width: size.width, height: size.height + 70)),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controlWindow.title = "VortexFlow Visual Preview — local fixture"
        controlWindow.isReleasedWhenClosed = false
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.appearance = NSAppearance(named: .darkAqua)
        controlWindow.contentView = NSHostingView(rootView: VStack(spacing: 0) {
            PreviewControls(model: model).frame(height: 70).background(.regularMaterial)
            ZStack {
                PreviewBackdrop(model: model)
                PreviewOverlay(model: model)
            }.frame(width: size.width, height: size.height)
        })
        model.onAppearance = { [weak controlWindow] dark in
            controlWindow?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controls = controlWindow
        overlay = controlWindow
        print("VISUAL_PREVIEW_READY panel=\(model.state.layout.panelSize) window=\(controlWindow.windowNumber)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct PreviewOverlay: View {
    @ObservedObject var model: PreviewModel
    var body: some View {
        OverlayView(state: model.state)
            .environment(\.colorScheme, model.dark ? .dark : .light)
            .environment(\.overlayReduceTransparencyOverride, model.opaque)
    }
}

private struct PreviewControls: View {
    @ObservedObject var model: PreviewModel
    var body: some View {
        HStack(spacing: 16) {
            Toggle("Dark appearance", isOn: $model.dark)
            Toggle("Pattern", isOn: $model.textured)
            Toggle("Invert backdrop", isOn: $model.invertBackdrop)
            Toggle("Opaque fallback", isOn: $model.opaque)
            Toggle("Animate hub", isOn: $model.motion)
            Button("Select next window") { model.selectNext() }
            Button("Close preview") { NSApp.terminate(nil) }
        }
        .toggleStyle(.checkbox)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewBackdrop: View {
    @ObservedObject var model: PreviewModel
    var body: some View {
        ZStack {
            ((model.dark != model.invertBackdrop) ? Color.black : Color(red: 0.92, green: 0.91, blue: 0.89))
            if model.textured {
                // A contrast/blur test pattern, not decorative product artwork.
                HStack(spacing: 0) {
                    ForEach(0..<18) { index in
                        (index.isMultiple(of: 2) ? Color.blue.opacity(0.65) : Color.orange.opacity(0.6))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("Backdrop detail · the glass should soften this pattern")
                        .font(.system(size: 25, weight: .medium)).padding(22).foregroundStyle(.white)
                }
            }
        }
        .ignoresSafeArea()
    }
}
#endif
