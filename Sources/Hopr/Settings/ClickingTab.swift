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
                    .accessibilityIdentifier("hint-shortcut-recorder")
                    .accessibilityLabel("Hint Mode activation shortcut")
                }
                ToggleRow("Auto-click on Single Match",
                          subtitle: "Immediately click when only one element matches",
                          isLast: false,
                          value: $settings.autoClick)
                .accessibilityIdentifier("auto-click-toggle")
                .accessibilityLabel("Auto-click on Single Match")
                .accessibilityHint("When enabled, automatically clicks if only one element matches the search")
                ToggleRow("Chain Clicks",
                          subtitle: "Stay in hint mode after clicking",
                          isLast: true,
                          value: $settings.chainClicks)
                .accessibilityIdentifier("chain-clicks-toggle")
                .accessibilityLabel("Chain Clicks")
                .accessibilityHint("When enabled, hint mode remains active after clicking an element")
            }

            // MARK: - Labels
            SettingsCard(title: "Labels") {
                LabeledRow("Characters", isLast: false) {
                    TextField("ABCDEF…", text: $settings.labelCharacters)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 180)
                        .accessibilityIdentifier("label-characters-input")
                        .accessibilityLabel("Label characters")
                        .accessibilityHint("Enter characters used to create hint labels (e.g., ABCDEFGHIJKLMNOPQRSTUVWXYZ)")
                }
            }

            // MARK: - Search
            SettingsCard(title: "Search") {
                LabeledRow("Search Shortcut", isLast: false) {
                    ShortcutRecorder(keyCombo: Binding(
                        get: { settings.searchShortcut },
                        set: { settings.searchShortcut = $0 }
                    ))
                    .accessibilityIdentifier("search-shortcut-recorder")
                    .accessibilityLabel("Search mode activation shortcut")
                }
                ToggleRow("Hide Labels Before Search",
                          subtitle: "Show labels only after typing begins",
                          isLast: true,
                          value: $settings.hideLabelsBeforeSearch)
                .accessibilityIdentifier("hide-labels-toggle")
                .accessibilityLabel("Hide Labels Before Search")
                .accessibilityHint("When enabled, element labels appear only after you start typing in search mode")
            }

            // MARK: - Focus Text
            SettingsCard(title: "Focus Text") {
                LabeledRow("Activation Shortcut", isLast: false) {
                    ShortcutRecorder(keyCombo: Binding(
                        get: { settings.focusTextShortcut },
                        set: { settings.focusTextShortcut = $0 }
                    ))
                    .accessibilityIdentifier("focus-text-shortcut-recorder")
                    .accessibilityLabel("Focus Text mode activation shortcut")
                }
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
                .accessibilityIdentifier("restore-defaults-button")
                .accessibilityLabel("Restore Defaults")
                .accessibilityHint("Resets all clicking mode settings to their default values")
            }
            .padding(.top, 5)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
