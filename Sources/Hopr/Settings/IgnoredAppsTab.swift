import SwiftUI
import AppKit

struct IgnoredAppsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showAppPicker = false
    @State private var ignoredAppNames: [String: (name: String, icon: NSImage?)] = [:]

    var body: some View {
        VStack(spacing: 0) {
            if settings.ignoredApps.isEmpty {
                // Empty state
                VStack(spacing: 10) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.15))
                            .frame(width: 60, height: 60)
                        Image(systemName: "xmark.app")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text("No Ignored Apps")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Apps added here won't show keyboard labels.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // App list
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.ignoredApps.enumerated()), id: \.element) { idx, bundleId in
                            let info = ignoredAppNames[bundleId]
                            let isLast = idx == settings.ignoredApps.count - 1

                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    // App icon
                                    Group {
                                        if let icon = info?.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 28, height: 28)
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color(nsColor: .separatorColor).opacity(0.3))
                                                .frame(width: 28, height: 28)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(info?.name ?? bundleId)
                                            .font(.system(size: 13))
                                        if info?.name != nil {
                                            Text(bundleId)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        withAnimation { removeApp(bundleId) }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(nsColor: .systemRed))
                                            .opacity(0.85)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)

                                if !isLast {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
                    .padding(20)
                }
            }

            // Bottom toolbar
            Divider()
            HStack {
                Text(settings.ignoredApps.isEmpty
                     ? "No apps ignored"
                     : "\(settings.ignoredApps.count) app\(settings.ignoredApps.count == 1 ? "" : "s") ignored")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()

                if !settings.ignoredApps.isEmpty {
                    Button("Restore Defaults") {
                        withAnimation {
                            settings.resetIgnoredAppsSettings()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    showAppPicker = true
                } label: {
                    Label("Add App", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .onAppear { loadAppNames() }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(selectedApps: $settings.ignoredApps)
        }
    }

    private func removeApp(_ bundleId: String) {
        settings.ignoredApps.removeAll { $0 == bundleId }
        ignoredAppNames.removeValue(forKey: bundleId)
    }

    private func loadAppNames() {
        for bundleId in settings.ignoredApps {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                ignoredAppNames[bundleId] = (name: name, icon: icon)
            }
        }
    }
}

// MARK: - App Picker Sheet
struct AppPickerView: View {
    @Binding var selectedApps: [String]
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var allApps: [(name: String, bundleId: String, icon: NSImage?)] = []

    private var filteredApps: [(name: String, bundleId: String, icon: NSImage?)] {
        if searchText.isEmpty { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Apps to Ignore")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search apps…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 12) {
                    ForEach(filteredApps, id: \.bundleId) { app in
                        let isSelected = selectedApps.contains(app.bundleId)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                toggleApp(app.bundleId)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        if let icon = app.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 44, height: 44)
                                        } else {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 44, height: 44)
                                        }
                                    }
                                    .opacity(isSelected ? 1.0 : 0.85)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(nsColor: .controlAccentColor))
                                            .background(Circle().fill(.white).padding(2))
                                            .offset(x: 4, y: -4)
                                    }
                                }

                                Text(app.name)
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70)
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected
                                          ? Color(nsColor: .controlAccentColor).opacity(0.12)
                                          : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color(nsColor: .controlAccentColor) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 520)
        .onAppear { loadApps() }
    }

    private func toggleApp(_ bundleId: String) {
        if selectedApps.contains(bundleId) {
            selectedApps.removeAll { $0 == bundleId }
        } else {
            selectedApps.append(bundleId)
        }
    }

    private func loadApps() {
        let workspace = NSWorkspace.shared
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        var apps: [(name: String, bundleId: String, icon: NSImage?)] = []
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(item)
                guard let bundle = Bundle(path: path),
                      let bundleId = bundle.bundleIdentifier else { continue }
                apps.append((
                    name: (item as NSString).deletingPathExtension,
                    bundleId: bundleId,
                    icon: workspace.icon(forFile: path)
                ))
            }
        }
        allApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
