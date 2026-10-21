import AppKit
import SwiftUI
import SwitchesCore

@main
struct SwitchesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: appDelegate.controller)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: appDelegate.controller)
        }
    }
}

private struct MenuBarLabel: View {
    let controller: EngineController

    var body: some View {
        if controller.isActive {
            Image("MenuBarIcon")
                .accessibilityLabel("Switches")
        } else {
            Image("MenuBarIconPaused")
                .accessibilityLabel("Switches (paused)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    let controller = EngineController(appState: AppState())
    private var onboardingWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        if !controller.permissions.isGranted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = OnboardingView(controller: controller) { [weak self] in
            self?.onboardingWindow?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Switches"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            onboardingWindow = nil
        }
    }
}
