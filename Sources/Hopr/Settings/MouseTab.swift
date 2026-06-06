import SwiftUI

struct MouseTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: - Mouse Mode
            SettingsCard(title: "Mouse Mode") {
                LabeledRow("Activation Shortcut", isLast: true) {
                    ShortcutRecorder(keyCombo: Binding(
                        get: { settings.mouseShortcut },
                        set: { settings.mouseShortcut = $0 }
                    ))
                }
            }

            // MARK: - Cursor Speed
            SettingsCard(title: "Cursor Speed") {
                SpeedSliderRow(label: "Normal Speed", isLast: false,
                               value: $settings.mouseSpeed, range: 5...30, step: 1)
                SpeedSliderRow(label: "Fast Speed  (hold ⇧)", isLast: true,
                               value: $settings.mouseFastSpeed, range: 20...100, step: 5)
            }

            // MARK: - Drag & Drop
            SettingsCard(title: "Drag & Drop") {
                LabeledRow("Drag Initiation Delay", isLast: true) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.mouseDragDelay, in: 0.05...0.60, step: 0.05)
                            .frame(width: 120)
                        Text(String(format: "%.0f ms", settings.mouseDragDelay * 1000))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            // Restore Defaults
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    withAnimation {
                        settings.resetMouseSettings()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 5)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
