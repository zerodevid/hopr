import SwiftUI

// MARK: - Shared design tokens
extension Color {
    static let cardBackground = Color(nsColor: .windowBackgroundColor).opacity(0.6)
}

// MARK: - Shared SettingsCard container
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Row containers
struct SettingsRow<Leading: View, Trailing: View>: View {
    let isLast: Bool
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                leading()
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if !isLast {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Label row (text left, custom right)
struct LabeledRow<Trailing: View>: View {
    let label: String
    let subtitle: String?
    let isLast: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(_ label: String, subtitle: String? = nil, isLast: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.subtitle = subtitle
        self.isLast = isLast
        self.trailing = trailing
    }

    var body: some View {
        SettingsRow(isLast: isLast) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13))
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        } trailing: {
            trailing()
        }
    }
}

// MARK: - Toggle row
struct ToggleRow: View {
    let label: String
    let subtitle: String?
    let isLast: Bool
    @Binding var value: Bool

    init(_ label: String, subtitle: String? = nil, isLast: Bool = false, value: Binding<Bool>) {
        self.label = label
        self.subtitle = subtitle
        self.isLast = isLast
        self._value = value
    }

    var body: some View {
        LabeledRow(label, subtitle: subtitle, isLast: isLast) {
            Toggle("", isOn: $value).labelsHidden()
        }
    }
}

// MARK: - Shortcut badge
struct ShortcutBadge: View {
    let keys: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys.map { String($0) }, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .controlColor))
                            .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Speed slider row
struct SpeedSliderRow: View {
    let label: String
    let isLast: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledRow(label, isLast: isLast) {
            HStack(spacing: 6) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Slider(value: $value, in: range, step: step)
                    .frame(width: 140)
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}
