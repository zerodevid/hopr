import SwiftUI

struct ClickingTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: - Hint Mode
            SettingsCard(title: "Hint Mode") {
                LabeledRow("Activation Shortcut", isLast: false) {
                    ShortcutRecorder(keyCombo: Binding(
                        get: { settings.hintShortcut },
                        set: { settings.hintShortcut = $0 }
                    ))
                }
                ToggleRow("Auto-click on Single Match",
                          subtitle: "Immediately click when only one element matches",
                          isLast: false,
                          value: $settings.autoClick)
                ToggleRow("Chain Clicks",
                          subtitle: "Stay in hint mode after clicking",
                          isLast: true,
                          value: $settings.chainClicks)
            }

            // MARK: - Labels
            SettingsCard(title: "Labels") {
                LabeledRow("Characters", isLast: false) {
                    TextField("ABCDEF…", text: $settings.labelCharacters)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 180)
                }
            }

            // MARK: - Search
            SettingsCard(title: "Search") {
                LabeledRow("Search Shortcut", isLast: false) {
                    ShortcutRecorder(keyCombo: Binding(
                        get: { settings.searchShortcut },
                        set: { settings.searchShortcut = $0 }
                    ))
                }
                ToggleRow("Hide Labels Before Search",
                          subtitle: "Show labels only after typing begins",
                          isLast: true,
                          value: $settings.hideLabelsBeforeSearch)
            }

            // Restore Defaults
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    withAnimation {
                        settings.resetClickingSettings()
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
