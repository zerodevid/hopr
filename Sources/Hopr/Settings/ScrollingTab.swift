import SwiftUI

struct ScrollingTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: - Scroll Mode
            SettingsCard(title: "Scroll Mode") {
                LabeledRow("Activation Shortcut", isLast: false) {
                    ShortcutRecorder(keyCombo: Binding(
                        get: { settings.scrollShortcut },
                        set: { settings.scrollShortcut = $0 }
                    ))
                }
                ToggleRow("Show Area Numbers",
                          subtitle: "Display numbered badges on scroll areas",
                          isLast: true,
                          value: $settings.showScrollAreaNumbers)
            }

            // MARK: - Speed
            SettingsCard(title: "Speed") {
                SpeedSliderRow(label: "Scroll Speed", isLast: false,
                               value: $settings.scrollSpeed, range: 2...20, step: 1)
                SpeedSliderRow(label: "Dash Speed",
                               isLast: true,
                               value: $settings.dashSpeed, range: 20...120, step: 5)
            }

            // Restore Defaults
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    withAnimation {
                        settings.resetScrollingSettings()
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
