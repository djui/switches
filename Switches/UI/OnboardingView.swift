import SwiftUI
import SwitchesCore

/// Walks the user through granting Input Monitoring, then starts listening.
struct OnboardingView: View {
    let controller: EngineController
    let onDone: () -> Void

    var body: some View {
        let granted = controller.permissions.isGranted

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Switches")
                        .font(.title2.weight(.semibold))
                    Text("Mechanical keyboard sounds for every key you press.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Switches needs **Input Monitoring** permission to notice key presses.")
                Text("It only sees which key moved, never what you type, and it has no network access.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Click **Open System Settings**.")
                step(2, "Turn on **Switches** under Privacy & Security › Input Monitoring.")
                step(3, "Come back here — Switches starts automatically.")
            }

            HStack {
                if granted {
                    Label("Permission granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Waiting for permission…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if granted {
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") {
                        controller.permissions.request()
                        controller.permissions.openSystemSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            while !Task.isCancelled {
                if controller.permissions.refresh() {
                    controller.startListening()
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(text)
        }
    }
}
