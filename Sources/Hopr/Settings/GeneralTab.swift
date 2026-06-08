import SwiftUI

// MARK: - GeneralTab

struct GeneralTab: View {
    @ObservedObject var settings = AppSettings.shared

    /// Two-way binding: Color ↔ hex string stored in AppStorage
    private var labelColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.labelBgColorHex) },
            set: { settings.labelBgColorHex = $0.hexString }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: — Appearance Card
            SettingsCard(title: "Appearance") {

                // Color picker row
                LabeledRow("Label Color",
                           subtitle: "Background color for keyboard hint labels",
                           isLast: false) {
                    HStack(spacing: 10) {
                        // Quick preset swatches
                        PresetSwatches(selectedHex: $settings.labelBgColorHex)
                        // Full color picker
                        ColorPicker("", selection: labelColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                    }
                }

                Divider().padding(.leading, 16)

                // Label size
                LabeledRow("Label Size", isLast: false) {
                    HStack(spacing: 6) {
                        Text("A")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Slider(value: $settings.labelSize, in: 10...24, step: 1)
                            .frame(width: 130)
                        Text("A")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Divider().padding(.leading, 16)

                // Indicator position
                LabeledRow("Indicator Position", isLast: false) {
                    Picker("", selection: $settings.modeIndicatorPosition) {
                        Text("Top").tag("top")
                        Text("Center").tag("center")
                        Text("Bottom").tag("bottom")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                }

                Divider().padding(.leading, 16)

                // Hint placement
                LabeledRow("Hint Placement", isLast: false) {
                    Picker("", selection: $settings.hintPlacement) {
                        Text("Top/Bottom").tag("aboveBelow")
                        Text("Left/Right (Dynamic)").tag("leftRight")
                        Text("Always Left").tag("left")
                        Text("Always Right").tag("right")
                        Text("Smart Auto").tag("auto")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                    .labelsHidden()
                }

                // Live Preview
                Divider().padding(.leading, 16)
                LabelPreviewPanel(settings: settings)
            }

            // MARK: — Application Card
            SettingsCard(title: "Application") {
                ToggleRow("Show Menubar Icon",
                          subtitle: "Access settings from the menu bar",
                          isLast: false,
                          value: $settings.showMenubarIcon)
                
                Divider().padding(.leading, 16)
                
                ToggleRow("Launch at Login",
                          subtitle: "Start Hopr automatically on startup",
                          isLast: false,
                          value: $settings.launchAtLogin)
                
                Divider().padding(.leading, 16)
                
                ToggleRow("Show HUD Notifications",
                          subtitle: "Show large mode banner above dock when activated",
                          isLast: true,
                          value: $settings.showModeNotification)
            }

            // Restore Defaults
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    withAnimation {
                        settings.resetGeneralSettings()
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

// MARK: - Preset Swatches

private let presetColors: [(name: String, hex: String)] = [
    ("Yellow",  "#FCDF22"),
    ("Blue",    "#007AFF"),
    ("Indigo",  "#5E5CE6"),
    ("Green",   "#30D158"),
    ("Orange",  "#FF9F0A"),
    ("Pink",    "#FF375F"),
    ("White",   "#FFFFFF"),
]

struct PresetSwatches: View {
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(presetColors, id: \.hex) { preset in
                let isSelected = selectedHex.uppercased() == preset.hex.uppercased()
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedHex = preset.hex
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: preset.hex))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(
                                    (NSColor(hex: preset.hex) ?? .black).isPerceptuallyLight
                                    ? Color.black : Color.white
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.12), value: isSelected)
            }
        }
    }
}

// MARK: - Live Preview Panel

struct LabelPreviewPanel: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PREVIEW")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                PreviewCanvas(isDark: true,  bgColorHex: settings.labelBgColorHex, labelSize: settings.labelSize)
                PreviewCanvas(isDark: false, bgColorHex: settings.labelBgColorHex, labelSize: settings.labelSize)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Preview Canvas (dark & light)

struct PreviewCanvas: View {
    let isDark: Bool
    let bgColorHex: String
    let labelSize: Double

    private var canvasBg: Color { isDark ? Color(white: 0.12) : Color(white: 0.95) }
    private var fakeElementColor: Color {
        isDark ? Color(white: 0.25) : Color(white: 0.82)
    }
    private var captionColor: Color {
        isDark ? Color(white: 0.45) : Color(white: 0.55)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(canvasBg)

            VStack(alignment: .leading, spacing: 6) {
                // Toolbar row: label bubble is ABOVE button in VStack — never clipped
                HStack(alignment: .bottom, spacing: 8) {
                    fakeButton(label: "AB", width: 52)
                    fakeButton(label: "CD", width: 44)
                    fakeButton(label: "EF", width: 60)
                    Spacer()
                }

                // Fake content lines
                fakeRect(width: 110, height: 7)
                fakeRect(width: 75,  height: 7)

                // Text field with label above it in VStack
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        LabelBubble(text: "GH",
                                    fontSize: labelSize,
                                    bgColorHex: bgColorHex)
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isDark ? Color(white: 0.18) : Color(white: 0.87))
                        .frame(height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(fakeElementColor, lineWidth: 0.5)
                        )
                }
            }
            .padding(12)

            // Caption badge
            Text(isDark ? "Dark" : "Light")
                .font(.system(size: 9))
                .foregroundColor(captionColor)
                .padding(6)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func fakeButton(label: String, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            LabelBubble(text: label,
                        fontSize: labelSize,
                        bgColorHex: bgColorHex)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fakeElementColor)
                .frame(width: width, height: 20)
        }
        .frame(width: width)
    }

    @ViewBuilder
    private func fakeRect(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fakeElementColor)
            .frame(width: width, height: height)
    }
}

// MARK: - Label Bubble (SwiftUI replica of LabelView)

struct LabelBubble: View {
    let text: String
    let fontSize: Double
    let bgColorHex: String

    private var nsBgColor: NSColor {
        NSColor(hex: bgColorHex) ?? .controlAccentColor
    }

    private var isLight: Bool {
        nsBgColor.isPerceptuallyLight
    }

    private var textColor: Color {
        isLight ? .black : .white
    }

    private var topColor: Color {
        let topBlend: CGFloat = isLight ? 0.25 : 0.38
        return Color(nsColor: nsBgColor.blended(withFraction: topBlend, of: .white) ?? nsBgColor)
    }

    private var bottomColor: Color {
        let bottomBlend: CGFloat = isLight ? 0.15 : 0.22
        return Color(nsColor: nsBgColor.blended(withFraction: bottomBlend, of: .black) ?? nsBgColor)
    }

    private var borderColor: Color {
        Color(nsColor: nsBgColor.blended(withFraction: 0.35, of: .black)?.withAlphaComponent(0.45)
            ?? NSColor.black.withAlphaComponent(0.2))
    }

    private var computedFontSize: CGFloat {
        let base = CGFloat(fontSize)
        return text.count <= 2 ? max(8, base * 0.65) : max(7, base * 0.57)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Bubble
            Text(text)
                .font(.system(size: computedFontSize, weight: .bold))
                .foregroundColor(textColor)
                .shadow(color: isLight ? .white.opacity(0.6) : .black.opacity(0.5), radius: 0.5, x: 0, y: 0.75)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    LinearGradient(
                        colors: [topColor, bottomColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.75)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isLight ? 0.50 : 0.25),
                                    .white.opacity(0.0),
                                    .black.opacity(isLight ? 0.14 : 0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                        .padding(0.75)
                )

            // Pointer triangle - matches bottom color for seamless blending
            LabelPointer()
                .fill(bottomColor)
                .frame(width: 8, height: 5)
                .overlay(
                    LabelPointer()
                        .stroke(borderColor, lineWidth: 0.75)
                )
        }
        .shadow(color: Color.black.opacity(0.45), radius: 3.5, x: 0, y: 2.5)
        .animation(.easeInOut(duration: 0.1), value: computedFontSize)
    }
}

/// Down-pointing triangle for label bubble pointer
struct LabelPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
