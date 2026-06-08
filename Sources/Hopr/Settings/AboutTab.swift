import SwiftUI

struct AboutTab: View {
    @ObservedObject var settings = AppSettings.shared

    private var appIcon: NSImage? {
        let fm = FileManager.default
        let localPath = fm.currentDirectoryPath + "/Resources/icon.png"
        let absolutePath = "/Users/macbook/Documents/Project/clone_hopr/Resources/icon.png"
        
        if fm.fileExists(atPath: localPath) {
            return NSImage(contentsOfFile: localPath)
        } else if fm.fileExists(atPath: absolutePath) {
            return NSImage(contentsOfFile: absolutePath)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero section
            VStack(spacing: 16) {
                if let nsImage = appIcon {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(nsColor: .controlAccentColor),
                                             Color(nsColor: .controlAccentColor).opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: Color(nsColor: .controlAccentColor).opacity(0.4), radius: 12, x: 0, y: 4)

                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                VStack(spacing: 4) {
                    Text("Hopr")
                        .font(.system(size: 20, weight: .bold))
                    Text("Version 1.0.0")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Keyboard-driven navigation for macOS")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 24)

            // Shortcut reference
            VStack(alignment: .leading, spacing: 0) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    AboutShortcutRow(keys: settings.hintShortcut.displayString, description: "Hint Mode — click UI elements", isLast: false)
                    AboutShortcutRow(keys: settings.scrollShortcut.displayString,     description: "Scroll Mode — use HJKL to scroll", isLast: false)
                    AboutShortcutRow(keys: settings.mouseShortcut.displayString,     description: "Mouse Mode — keyboard cursor control", isLast: false)
                    AboutShortcutRow(keys: settings.searchShortcut.displayString,     description: "Search Mode — find by label text", isLast: false)
                    AboutShortcutRow(keys: "Esc",      description: "Exit any active mode", isLast: true)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
            }

            Spacer()

            // Footer
            Text("Built with ❤️ for keyboard-first users")
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.6))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutShortcutRow: View {
    let keys: String
    let description: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(nsColor: .controlAccentColor))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlAccentColor).opacity(0.1))
                    )
                    .frame(minWidth: 80, alignment: .center)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            if !isLast {
                Divider().padding(.leading, 14)
            }
        }
    }
}
