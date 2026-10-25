import AppKit
import SwiftUI
import SwitchesCore

struct SettingsView: View {
    let controller: EngineController

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            SoundSettingsView(controller: controller)
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            PausingSettingsView(controller: controller)
                .tabItem { Label("Pausing", systemImage: "pause.circle") }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    let controller: EngineController

    var body: some View {
        @Bindable var appState = controller.appState
        let launch = controller.launchAtLogin

        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launch.isEnabled },
                    set: { launch.setEnabled($0) }
                ))
                if launch.requiresApproval {
                    HStack {
                        Text("Approve Switches in System Settings › Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { launch.openSystemSettings() }
                    }
                }
                if let error = launch.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Keyboard layout", selection: $appState.keyboardLayout) {
                    ForEach(KeyboardLayoutKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            } footer: {
                Text("Used to place each key's sound left or right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Input Monitoring") {
                    if controller.permissions.isGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant…") { AppDelegate.shared?.showOnboarding() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launch.refresh()
            controller.permissions.refresh()
        }
    }
}

// MARK: - Sound

private struct SoundSettingsView: View {
    let controller: EngineController

    var body: some View {
        @Bindable var appState = controller.appState

        Form {
            Section {
                LabeledContent("Volume") {
                    VolumeSlider(volume: $appState.volume)
                        .frame(width: 260)
                }
                Picker("Theme", selection: Binding(
                    get: { appState.selectedTheme ?? controller.themeNames.first ?? "" },
                    set: { appState.selectedTheme = $0 }
                )) {
                    ForEach(controller.themeNames, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Spacer()
                    Button("Preview") { controller.playPreview() }
                        .disabled(controller.loadedThemeName == nil)
                }
            }

            Section("Spatial") {
                LabeledContent("Stereo width") {
                    ValueSlider(value: $appState.spatialWidth, range: 0...1) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                }
                Toggle("Headphone mode (adds interaural delay)", isOn: $appState.headphoneMode)
            }

            Section {
                LabeledContent("Pitch") {
                    ValueSlider(value: $appState.pitchSemitones, range: -12...12, step: 1,
                                onRelease: controller.playPreview) {
                        "\(signed($0)) st"
                    }
                }
                LabeledContent("Bass") {
                    ValueSlider(value: $appState.bassDb, range: -12...12, step: 1,
                                onRelease: controller.playPreview) {
                        "\(signed($0)) dB"
                    }
                }
                LabeledContent("Treble") {
                    ValueSlider(value: $appState.trebleDb, range: -12...12, step: 1,
                                onRelease: controller.playPreview) {
                        "\(signed($0)) dB"
                    }
                }
            } header: {
                SectionHeader(title: "Tone") { appState.resetTone() }
            } footer: {
                Text("Pitch shifts every sound up or down (lower also rings a little longer). Bass and treble shape the tone without changing timing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Pitch variation") {
                    ValueSlider(value: $appState.pitchVariance, range: 0...0.1) {
                        "±\(Int(($0 * 100).rounded()))%"
                    }
                }
                LabeledContent("Volume variation") {
                    ValueSlider(value: $appState.volumeVarianceDb, range: 0...6) {
                        String(format: "±%.1f dB", $0)
                    }
                }
                LabeledContent("Key-up level") {
                    ValueSlider(value: $appState.upGainDb, range: -24...0) {
                        "\(signed($0)) dB"
                    }
                }
                Toggle("Ignore key auto-repeat", isOn: $appState.ignoreAutorepeat)
            } header: {
                SectionHeader(title: "Variation") { appState.resetVariation() }
            }

            Section {
                Label {
                    Text("Bluetooth headphones and speakers add 100–200 ms of delay that Switches can't remove. Use wired or built-in output for instant clicks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// "+3", "−3" or "0", with a typographic minus.
private func signed(_ value: Double) -> String {
    let n = Int(value.rounded())
    return n > 0 ? "+\(n)" : n < 0 ? "−\(-n)" : "0"
}

/// Slider with a fixed-width readout, so every slider in the form has the same length.
private struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var onRelease: (() -> Void)? = nil
    let format: (Double) -> String

    var body: some View {
        HStack {
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step, onEditingChanged: editingChanged)
                } else {
                    Slider(value: $value, in: range, onEditingChanged: editingChanged)
                }
            }
            Text(format(value))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: 260)
    }

    private func editingChanged(_ editing: Bool) {
        if !editing { onRelease?() }
    }
}

private struct SectionHeader: View {
    let title: String
    let reset: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("Reset", action: reset)
                .controlSize(.small)
        }
    }
}

// MARK: - Pausing

private struct PausingSettingsView: View {
    let controller: EngineController

    var body: some View {
        @Bindable var appState = controller.appState

        Form {
            Section {
                Toggle("Pause sounds", isOn: $appState.paused)
                Toggle("Toggle with \(PauseController.hotkeyDescription)", isOn: $appState.hotkeyEnabled)
            }

            Section("Automatically pause") {
                Toggle("While a game is in front", isOn: $appState.pauseForGames)
                Toggle("While any app is full screen", isOn: $appState.pauseInFullscreen)
                Toggle("During secure text entry (passwords)", isOn: $appState.pauseOnSecureInput)
            }

            Section {
                if appState.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        AppRow(bundleID: bundleID)
                        Spacer()
                        Button {
                            appState.excludedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(bundleID)")
                    }
                }
                Menu("Add Running App") {
                    ForEach(runningApps(excluding: appState.excludedBundleIDs), id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            if let id = app.bundleIdentifier { appState.excludedBundleIDs.append(id) }
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Sounds are muted while one of these apps is in front.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func runningApps(excluding excluded: [String]) -> [NSRunningApplication] {
        let ownID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != nil && $0.bundleIdentifier != ownID }
            .filter { !excluded.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") .localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }
}

private struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}
