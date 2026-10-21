import SwiftUI

/// Safety playbook: every approach in one line (Toolkit), research questions as decision maps (Experiments), and a recall drill.
struct PlaybookView: View {
    enum Part: String, CaseIterable, Identifiable {
        case experiments = "Experiments", toolkit = "Toolkit", drill = "Drill"
        var id: String { rawValue }
    }

    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("playbookPart") private var part = Part.experiments
    @State private var filter = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Part", selection: $part) {
                        ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let playbook = store.playbook {
                        switch part {
                        case .experiments: experiments(playbook)
                        case .toolkit: toolkit(playbook)
                        case .drill: DrillView(playbook: playbook)
                        }
                    } else {
                        ContentUnavailableView("Playbook not built", systemImage: "map", description: Text("Run app/tools/build_content.py."))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .navigationTitle("Playbook")
            .searchable(text: $filter, prompt: part == .toolkit ? "Find a tool" : "Find a question")
            .withRoutes()
            .onAppear {
                if let route = router.pendingPlaybook {
                    router.pendingPlaybook = nil
                    path.append(route)
                }
            }
        }
    }

    private func matches(_ texts: String...) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || texts.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Experiments

    @ViewBuilder
    private func experiments(_ playbook: Playbook) -> some View {
        if filter.isEmpty {
            RecipeStrip(recipe: playbook.recipe)
        }
        let themes = playbook.experiments.reduce(into: [String]()) { if !$0.contains($1.theme) { $0.append($1.theme) } }
        ForEach(themes, id: \.self) { theme in
            let items = playbook.experiments.filter { $0.theme == theme && matches($0.question, $0.chain, $0.theme) }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: theme, symbol: Playbook.themeSymbol(theme), tint: Playbook.themeTint(theme))
                    ForEach(items) { e in
                        NavigationLink(value: Route.experiment(e.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(e.question)
                                    .font(.serif(.headline, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(e.chain)
                                    .font(.rounded(.caption, weight: .medium))
                                    .foregroundStyle(Playbook.themeTint(theme))
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(radius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Toolkit

    @ViewBuilder
    private func toolkit(_ playbook: Playbook) -> some View {
        let categories = playbook.tools.reduce(into: [String]()) { if !$0.contains($1.category) { $0.append($1.category) } }
        ForEach(categories, id: \.self) { category in
            let items = playbook.tools.filter { $0.category == category && matches($0.name, $0.what, $0.useWhen) }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: category, symbol: Playbook.categorySymbol(category), tint: Playbook.categoryTint(category))
                    VStack(spacing: 0) {
                        ForEach(items) { tool in
                            NavigationLink(value: Route.tool(tool.id)) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tool.name)
                                            .font(.serif(.body, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text(tool.what)
                                            .font(.rounded(.subheadline))
                                            .foregroundStyle(Theme.inkSecondary)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.inkTertiary)
                                        .padding(.top, 4)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if tool.id != items.last?.id { Divider().padding(.leading, 14) }
                        }
                    }
                    .card(radius: 16)
                }
            }
        }
    }
}

/// The generic recipe, numbered, above the experiment list.
private struct RecipeStrip: View {
    let recipe: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE RECIPE BEHIND EVERY MAP")
                .font(.rounded(.caption2, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Theme.accent)
            FlowLayout(spacing: 6) {
                ForEach(Array(recipe.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 6) {
                        Text("\(i + 1)")
                            .font(.rounded(.caption2, weight: .bold))
                            .foregroundStyle(Theme.onTint)
                            .frame(width: 18, height: 18)
                            .background(Theme.accent, in: Circle())
                        Text(step)
                            .font(.rounded(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        if i < recipe.count - 1 {
                            Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Experiment map

struct ExperimentMapView: View {
    let experiment: Experiment
    @Environment(ContentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let tint = Playbook.themeTint(experiment.theme)
        let route = experiment.chain.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let forks = experiment.tree.filter { !($0.branches ?? []).isEmpty }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Pill(text: experiment.theme, symbol: Playbook.themeSymbol(experiment.theme), tint: tint)
                    Text(experiment.question)
                        .font(.serif(.title2, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(experiment.tree.count) steps" + (forks > 0 ? " · \(forks) decision \(forks == 1 ? "point" : "points")" : ""))
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.inkSecondary)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(route.enumerated()), id: \.offset) { i, step in
                            HStack(spacing: 6) {
                                Text("\(i + 1)")
                                    .font(.rounded(.caption2, weight: .bold))
                                    .foregroundStyle(tint)
                                    .frame(width: 18, height: 18)
                                    .background(tint.opacity(0.16), in: Circle())
                                Text(step)
                                    .font(.rounded(.caption, weight: .medium))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .padding(.vertical, 4)
                            .background(Theme.sunken, in: Capsule())
                            .overlay(Capsule().stroke(Theme.hairline))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("At a glance: " + route.joined(separator: ", then "))
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(experiment.tree.enumerated()), id: \.offset) { i, node in
                        StepCard(node: node, number: i + 1, tint: tint, isLast: i == experiment.tree.count - 1)
                    }
                }

                VStack(spacing: 12) {
                    InfoRow(title: "Watch out", text: experiment.confound, symbol: "exclamationmark.triangle.fill", tint: Theme.tint("coral"))
                    InfoRow(title: "Success looks like", text: experiment.success, symbol: "checkmark.seal.fill", tint: Theme.tint("lime"))
                    if !experiment.example.isEmpty {
                        InfoRow(title: "Real example", text: experiment.example, symbol: "doc.text.magnifyingglass", tint: Theme.tint("violet"))
                    }
                }

                if let id = experiment.fellowship, let book = store.books[id] {
                    Button { router.read(book) } label: {
                        Label("Read the fellowship book: \(book.title)", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One top-level step: numbered marker on a rail, the step as a card, its decision as an open fork below.
private struct StepCard: View {
    let node: TreeNode
    let number: Int
    let tint: Color
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Text("\(number)")
                    .font(.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.onTint)
                    .frame(width: 30, height: 30)
                    .background(tint, in: Circle())
                if !isLast {
                    Rectangle().fill(Theme.hairline).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 14)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    StepBody(node: node, titleFont: .serif(.headline, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 16)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Step \(number)")

                if let branches = node.branches, !branches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Decision: what did you find?", systemImage: "arrow.turn.down.right")
                            .font(.rounded(.caption2, weight: .bold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkTertiary)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 10) { branchCards(branches, minWidth: 220) }
                            VStack(alignment: .leading, spacing: 10) { branchCards(branches, minWidth: 0) }
                        }
                    }
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.hairline).frame(width: 2)
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    private func branchCards(_ branches: [Branch], minWidth: CGFloat) -> some View {
        ForEach(Array(branches.enumerated()), id: \.offset) { i, branch in
            BranchCard(branch: branch, color: Playbook.branchTints[i % Playbook.branchTints.count])
                .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One outcome of a decision: a coloured "If ..." tag over its follow-up steps.
private struct BranchCard: View {
    let branch: Branch
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If " + branch.condition.replacingOccurrences(of: "^[Ii]f\\s+", with: "", options: .regularExpression))
                .font(.rounded(.footnote, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(color.opacity(0.13), in: Capsule())
            ForEach(Array(branch.then.enumerated()), id: \.offset) { i, node in
                if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                VStack(alignment: .leading, spacing: 5) {
                    StepBody(node: node, titleFont: .rounded(.callout, weight: .semibold))
                    ForEach(Array((node.branches ?? []).enumerated()), id: \.offset) { _, nested in
                        BranchCard(branch: nested, color: color).padding(.top, 6)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(color)
                .frame(height: 3)
        }
    }
}

/// Title, how-to, tool link and outcome; shared by steps and branch steps.
private struct StepBody: View {
    let node: TreeNode
    let titleFont: Font
    @Environment(ContentStore.self) private var store

    var body: some View {
        Text(node.step)
            .font(titleFont)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
        if let how = node.how, !how.isEmpty {
            Text(how)
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let id = node.tool, let tool = store.toolsById[id] {
            NavigationLink(value: Route.tool(id)) {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(Playbook.categoryTint(tool.category))
                    Text(tool.name)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .font(.rounded(.caption, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.hairline))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        if let outcome = node.outcome, !outcome.isEmpty {
            Label {
                Text(outcome).foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "flag.checkered").foregroundStyle(Theme.tint("lime"))
            }
            .font(.rounded(.subheadline, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InfoRow: View {
    let title: String
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.rounded(.caption2, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(tint)
                Text(text)
                    .font(.serif(.body))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card(radius: 16)
    }
}

// MARK: - Tool detail

struct ToolDetailView: View {
    let tool: Tool
    @Environment(ContentStore.self) private var store

    var body: some View {
        let tint = Playbook.categoryTint(tool.category)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Pill(text: tool.category, symbol: Playbook.categorySymbol(tool.category), tint: tint)
                    Text(tool.name)
                        .font(.serif(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) {
                    InfoRow(title: "What it is", text: tool.what, symbol: "lightbulb.fill", tint: tint)
                    InfoRow(title: "Use it when", text: tool.useWhen, symbol: "questionmark.circle.fill", tint: Theme.tint("teal"))
                    InfoRow(title: "Catch", text: tool.limit, symbol: "exclamationmark.triangle.fill", tint: Theme.tint("coral"))
                }

                let terms = tool.terms.compactMap { store.terms[$0] }
                if !terms.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("In the glossary").font(.serif(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                        FlowLayout(spacing: 8) {
                            ForEach(terms) { term in
                                NavigationLink(value: Route.term(term.id)) {
                                    Text(term.term)
                                        .font(.rounded(.subheadline, weight: .medium))
                                        .foregroundStyle(Theme.categoryTint(term.category))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Theme.categoryTint(term.category).opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let used = store.experiments(using: tool.id)
                if !used.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Used in \(used.count) \(used.count == 1 ? "experiment" : "experiments")")
                            .font(.serif(.headline, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        ForEach(used) { e in
                            NavigationLink(value: Route.experiment(e.id)) {
                                HStack {
                                    Text(e.question)
                                        .font(.serif(.subheadline, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                                }
                                .padding(12)
                                .card(radius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Styling

extension Playbook {
    static let branchTints = [Theme.tint("teal"), Theme.tint("amber"), Theme.tint("violet")]

    static func themeTint(_ theme: String) -> Color {
        switch theme {
        case "Evals & deception": Theme.tint("violet")
        case "Training failures": Theme.tint("coral")
        case "Monitoring & control": Theme.tint("teal")
        case "Interp & robustness": Theme.tint("amber")
        default: Theme.accent
        }
    }

    static func themeSymbol(_ theme: String) -> String {
        switch theme {
        case "Evals & deception": "theatermasks"
        case "Training failures": "exclamationmark.arrow.triangle.2.circlepath"
        case "Monitoring & control": "eye"
        case "Interp & robustness": "magnifyingglass"
        default: "map"
        }
    }

    static func categoryTint(_ category: String) -> Color {
        switch category {
        case "Look inside", "Steer & edit": Theme.tint("teal")
        case "Measure & evaluate": Theme.tint("violet")
        case "Data & model organisms": Theme.tint("amber")
        case "Oversee & control": Theme.tint("coral")
        case "Train for alignment": Theme.tint("lime")
        default: Theme.accent
        }
    }

    static func categorySymbol(_ category: String) -> String {
        switch category {
        case "Look inside": "magnifyingglass"
        case "Steer & edit": "slider.horizontal.3"
        case "Measure & evaluate": "ruler"
        case "Data & model organisms": "testtube.2"
        case "Oversee & control": "eye"
        case "Train for alignment": "graduationcap"
        case "Governance & security": "building.columns"
        default: "wrench.and.screwdriver"
        }
    }
}
