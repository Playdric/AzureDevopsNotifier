import ADOCore
import SwiftUI

/// Actions qui quittent le panneau : il se ferme d'abord (AC39, AC40).
struct PanelNavigation {
    var openURL: (URL) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openSetup: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var panelNavigation = PanelNavigation()
}

/// Panneau option B : bandeaux, 3 sections repliables, barre d'actions.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var navigation: PanelNavigation {
        PanelNavigation(
            openURL: { url in
                dismiss()
                model.open(url)
            },
            openSettings: {
                dismiss()
                openSettings()
                NSApp.activate()
            },
            openSetup: {
                dismiss()
                openWindow(id: SetupView.windowID)
                NSApp.activate()
            })
    }

    var body: some View {
        let panel = model.panel
        VStack(spacing: 0) {
            if !panel.isConfigured {
                NotConfiguredView()
            } else {
                ForEach(Array(panel.banners.enumerated()), id: \.offset) { _, banner in
                    StatusBanner(banner: banner)
                }
                ScrollView {
                    // Titres de section épinglés pendant le défilement de leur liste.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        PRSection(
                            key: "review", title: "To Review", section: panel.toReview, loading: panel.isLoading,
                            empty: "No pull requests waiting for your review.", kind: .review)
                        PRSection(
                            key: "mine", title: "My PRs", section: panel.myPRs, loading: panel.isLoading,
                            empty: "You have no active pull requests.", kind: .mine)
                        WISection(section: panel.workItems, loading: panel.isLoading)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                PanelFooter(panel: panel)
            }
        }
        .frame(width: model.prefs.panelWidth.points)
        .environment(\.panelNavigation, navigation)
        .onDisappear { model.panelClosed() }
    }
}

struct NotConfiguredView: View {
    @Environment(\.panelNavigation) private var navigation

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Not Configured").font(.headline)
            Text("Connect to your Azure DevOps organization to see pull requests and work items.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Set Up…") { navigation.openSetup() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
        }
        .padding(24)
        Divider()
        HStack {
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(8)
    }
}

struct SectionHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let key: String
    let title: String
    let count: Int?

    var body: some View {
        let collapsed = model.prefs.collapsedSections.contains(key)
        Button {
            model.toggleSection(key)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                Text(title)
                Spacer()
                if let count { Text("\(count)").foregroundStyle(.tertiary).fontWeight(.regular) }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            // Capsule façon verre dessinée à la main : `.glassEffect` sur le panneau déjà en verre
            // se fond dans le fond et devient invisible.
            .background { GlassCapsule(dark: colorScheme == .dark) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }
}

struct SectionBody<Row: Equatable & Sendable & Identifiable, Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelNavigation) private var navigation
    let section: PanelSection<Row>
    let loading: Bool
    let empty: String
    let noun: String
    @ViewBuilder let row: (Row) -> Content

    var body: some View {
        if loading {
            ForEach(0..<2, id: \.self) { _ in SkeletonRow() }
        } else if section.rows.isEmpty {
            Text(empty)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 23)
                .padding(.vertical, 6)
        } else {
            ForEach(section.rows) { row($0) }
            if let url = section.overflowURL {
                Button("Show all \(section.total) \(noun) in browser…") { navigation.openURL(url) }
                    .buttonStyle(.link)
                    .font(.callout)
                    .padding(.leading, 23)
                    .padding(.vertical, 6)
            }
        }
        if !loading, section.hiddenCount > 0 {
            Text("\(section.hiddenCount) hidden")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 23)
                .padding(.bottom, 4)
                .help(
                    model.prefs.notifyHiddenItems
                        ? "Hidden by your display settings. Notifications are still sent."
                        : "Hidden by your display settings.")
        }
    }
}

struct PRSection: View {
    @Environment(AppModel.self) private var model
    let key: String
    let title: String
    let section: PanelSection<PRRow>
    let loading: Bool
    let empty: String
    let kind: PRRowView.Kind

    var body: some View {
        Section {
            if !model.prefs.collapsedSections.contains(key) {
                SectionBody(section: section, loading: loading, empty: empty, noun: "pull requests") {
                    PRRowView(row: $0, kind: kind)
                }
            }
        } header: {
            SectionHeader(key: key, title: title, count: loading ? nil : section.total)
        }
    }
}

struct WISection: View {
    @Environment(AppModel.self) private var model
    let section: PanelSection<WIRow>
    let loading: Bool

    var body: some View {
        Section {
            if !model.prefs.collapsedSections.contains("wi") {
                SectionBody(
                    section: section, loading: loading, empty: "No open work items assigned to you.", noun: "work items"
                ) {
                    WIRowView(row: $0)
                }
            }
        } header: {
            SectionHeader(key: "wi", title: "Work Items", count: loading ? nil : section.total)
        }
    }
}

struct SkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4).frame(width: 240, height: 10)
            RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 8)
        }
        .foregroundStyle(.quaternary)
        .padding(.leading, 23)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

/// Capsule translucide : flou du contenu dessous, voile clair, reflet en haut, bordure fine, ombre.
struct GlassCapsule: View {
    let dark: Bool

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.white.opacity(dark ? 0.10 : 0.38))
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(dark ? 0.28 : 0.85), .white.opacity(dark ? 0.08 : 0.35)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(dark ? 0.40 : 0.12), radius: 4, y: 2)
    }
}
