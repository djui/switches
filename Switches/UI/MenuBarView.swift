import AppKit
import SwiftUI
import SwitchesCore

struct MenuBarView: View {
    @Bindable var controller: EngineController
    @Environment(\.openSettings) private var openSettings

    private var appState: AppState { controller.appState }

    var body: some View {
        @Bindable var appState = controller.appState

        VStack(alignment: .leading, spacing: 12) {
            header

            if !controller.permissions.isGranted {
                permissionBanner
            }

            Toggle(isOn: $appState.paused) {
                HStack {
                    Text("Pause sounds")
                    Spacer()
                    Text(PauseController.hotkeyDescription)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .toggleStyle(.switch)

            Picker("Theme", selection: themeBinding) {
                ForEach(controller.themeNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .disabled(controller.themeNames.isEmpty)

            VolumeSlider(volume: $appState.volume)

            Divider()

            Button {
                NSApp.activate()
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Switches", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 280)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.isActive ? "keyboard.fill" : "keyboard")
                .font(.title2)
                .foregroundStyle(controller.isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Switches").font(.headline)
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Input Monitoring is off", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout.weight(.medium))
            Button("Grant Permission…") {
                AppDelegate.shared?.showOnboarding()
            }
        }
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { appState.selectedTheme ?? controller.themeNames.first ?? "" },
            set: { appState.selectedTheme = $0 }
        )
    }
}

struct VolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume <= 0 ? "speaker.slash.fill" : "speaker.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: $volume, in: 0...1)
                .accessibilityLabel("Volume")
            Text("\(Int((volume * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
