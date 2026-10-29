import ADOCore
import SwiftUI

/// Fond au survol des lignes, rayon 8.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowHover(pressed: configuration.isPressed) { configuration.label }
    }
}

struct RowHover<Content: View>: View {
    var pressed = false
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(pressed ? 0.1 : hovering ? 0.06 : 0))
            )
            .contentShape(.rect)
            .onHover { hovering = $0 }
    }
}

struct NewDot: View {
    let isNew: Bool

    var body: some View {
        Circle()
            .fill(isNew ? Color.accentColor : .clear)
            .frame(width: 7, height: 7)
            .accessibilityLabel(isNew ? "New" : "")
            .accessibilityHidden(!isNew)
    }
}

struct DraftBadge: View {
    var body: some View {
        Text("DRAFT")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .rect(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}

struct ReadyBadge: View {
    var body: some View {
        Text("READY")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.green.opacity(0.18), in: .rect(cornerRadius: 4))
            .foregroundStyle(.green)
            .accessibilityLabel("Ready to merge")
    }
}

/// Une pastille par pipeline de build validation, ordre ADO. Détail en popover au survol.
struct CIDots: View {
    static let maxDots = 6
    /// Popover plutôt que `.help` : délai maîtrisé, pastilles colorées dans le détail.
    static let hoverDelay = Duration.milliseconds(300)
    let row: PRRow
    @State private var hovering = false
    @State private var showsDetail = false

    var body: some View {
        if let label = row.ciAccessibilityLabel {
            HStack(spacing: 3) {
                ForEach(row.pipelines.prefix(Self.maxDots)) { pipeline in
                    PipelineDot(pipeline: pipeline)
                }
                if row.pipelines.count > Self.maxDots {
                    Text("+\(row.pipelines.count - Self.maxDots)").font(.system(size: 10))
                }
            }
            .padding(.vertical, 3)
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .task(id: hovering) {
                guard hovering else {
                    showsDetail = false
                    return
                }
                try? await Task.sleep(for: Self.hoverDelay)
                if !Task.isCancelled { showsDetail = true }
            }
            .popover(isPresented: $showsDetail, arrowEdge: .bottom) { CIDetail(row: row) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }
}

struct PipelineDot: View {
    let pipeline: PipelineCheck

    var body: some View {
        Group {
            switch pipeline.status {
            case .failed: Circle().fill(.red)
            case .passed: Circle().fill(.green)
            case .running: Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            case .queued, .expired: Circle().strokeBorder(.tertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
        .opacity(pipeline.isRequired ? 1 : 0.45)
    }
}

struct CIDetail: View {
    let row: PRRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let header = row.ciHeader {
                Text(header).fontWeight(.semibold)
            }
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                ForEach(row.pipelines) { pipeline in
                    GridRow {
                        PipelineDot(pipeline: pipeline)
                        HStack(spacing: 4) {
                            Text(pipeline.name)
                            if !pipeline.isRequired { Text("optional").foregroundStyle(.secondary) }
                        }
                        Text(pipeline.status.label).foregroundStyle(.secondary)
                    }
                }
            }
            if row.isReady {
                Label("Ready to merge", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.caption)
        .padding(10)
        .fixedSize()
    }
}

struct VoteSummary: View {
    let votes: [VoteCount]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(votes, id: \.vote) { item in
                HStack(spacing: 1) {
                    Image(systemName: Self.symbol(item.vote))
                    if item.count > 1 { Text("\(item.count)").font(.system(size: 10)) }
                }
                .foregroundStyle(Self.color(item.vote))
                .help("\(item.count) \(item.vote.label.lowercased())")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.count) \(item.vote.label.lowercased())")
            }
        }
        .font(.system(size: 10, weight: .semibold))
    }

    static func symbol(_ vote: Vote) -> String {
        switch vote {
        case .approved: "checkmark"
        case .approvedWithSuggestions: "checkmark.bubble"
        case .waitingForAuthor: "pause.fill"
        case .rejected: "xmark"
        case .none: "circle"
        }
    }

    static func color(_ vote: Vote) -> Color {
        switch vote {
        case .approved, .approvedWithSuggestions: .green
        case .waitingForAuthor: .orange
        case .rejected: .red
        case .none: .secondary
        }
    }
}

enum RelativeAge {
    static func short(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(max(1, minutes))m" }
        if minutes < 60 * 24 { return "\(minutes / 60)h" }
        return "\(minutes / (60 * 24))d"
    }
}

struct PRRowView: View {
    enum Kind { case review, mine }

    @Environment(AppModel.self) private var model
    @Environment(\.panelNavigation) private var navigation
    let row: PRRow
    let kind: Kind

    var body: some View {
        Button {
            navigation.openURL(row.url)
        } label: {
            HStack(spacing: 8) {
                NewDot(isNew: row.isNew)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if row.isDraft { DraftBadge() }
                        if row.isReady { ReadyBadge() }
                        // Sur le titre seul : pas sur toute la ligne (pastilles CI, votes).
                        Text(row.title).lineLimit(model.prefs.wrapTitles ? 2 : 1).truncationMode(.tail)
                            .help(row.originalTitle)
                    }
                    HStack(spacing: 4) {
                        switch kind {
                        case .review:
                            Text(
                                "\(row.repository) · \(row.author) · \(RelativeAge.short(row.created, now: model.now))")
                            Spacer()
                            CIDots(row: row)
                        case .mine:
                            Text("\(row.repository) · \(RelativeAge.short(row.created, now: model.now))")
                            Spacer()
                            HStack(spacing: 8) {
                                CIDots(row: row)
                                VoteSummary(votes: row.votes)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(RowButtonStyle())
    }
}

struct WIRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelNavigation) private var navigation
    let row: WIRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    navigation.openURL(row.url)
                } label: {
                    HStack(spacing: 8) {
                        NewDot(isNew: row.isNew)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("#\(String(row.id))").foregroundStyle(.secondary).monospacedDigit()
                                Text(row.title).lineLimit(model.prefs.wrapTitles ? 2 : 1).truncationMode(.tail)
                            }
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: row.typeColor) ?? .gray)
                                    .frame(width: 8, height: 8)
                                Text("\(row.typeName) · \(row.project)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .help(row.originalTitle)
                StatePill(row: row)
            }
            .modifier(RowHoverModifier())

            if let error = model.rowErrors[row.id] {
                InlineRowError(target: error.targetState, message: error.message) { model.dismissRowError(row.id) }
            }
        }
    }
}

struct RowHoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        RowHover { content }
    }
}

struct StatePill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelNavigation) private var navigation
    let row: WIRow

    var body: some View {
        let pending = model.pendingStates[row.id]
        Menu {
            Section("Move to") {
                if row.stateOptions.isEmpty {
                    Button("No state available") {}.disabled(true)
                }
                ForEach(row.stateOptions, id: \.name) { state in
                    Button {
                        model.changeState(workItemID: row.id, to: state.name)
                    } label: {
                        Label {
                            Text(state.name)
                        } icon: {
                            CategoryDot(category: state.category)
                        }
                    }
                }
            }
            Divider()
            Button("Open in Browser") { navigation.openURL(row.url) }
        } label: {
            HStack(spacing: 5) {
                if pending != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    CategoryDot(category: row.category)
                }
                Text(pending ?? row.state)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.caption)
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: .capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(pending != nil)
        .accessibilityLabel("State: \(row.state). Change state")
    }
}

struct CategoryDot: View {
    let category: StateCategory?

    var body: some View {
        Circle().fill(Self.color(category)).frame(width: 7, height: 7)
    }

    static func color(_ category: StateCategory?) -> Color {
        switch category {
        case .proposed, nil: .gray
        case .inProgress: .accentColor
        case .resolved: .orange
        case .completed: .green
        case .removed: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

struct InlineRowError: View {
    let target: String
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't change state to \(target).").fontWeight(.semibold)
                Text(message).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
        }
        .font(.caption)
        .padding(8)
        .background(.red.opacity(0.12), in: .rect(cornerRadius: 6))
        .padding(.leading, 23)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    /// Couleur de type WI ADO (`CC293D`).
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
