import SwiftUI

/// Recall drill: see a research question, recall the steps, reveal them one by one. Plus a tool-matching quiz.
struct DrillView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case recall = "Recall the map", match = "Match the tool"
        var id: String { rawValue }
    }

    let playbook: Playbook
    @State private var mode = Mode.recall

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Drill", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch mode {
            case .recall: RecallDrill(experiments: playbook.experiments)
            case .match: ToolMatchDrill(playbook: playbook)
            }
        }
    }
}

// MARK: - Recall

private struct RecallDrill: View {
    let experiments: [Experiment]
    @Environment(ContentStore.self) private var store
    // ponytail: mastered ids as one comma-joined string; a set in AppStorage needs no more for ~20 items.
    @AppStorage("playbookMastered") private var masteredRaw = ""
    @State private var current: Experiment?
    @State private var revealed = 0

    private var mastered: Set<String> { Set(masteredRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(mastered.intersection(experiments.map(\.id)).count) of \(experiments.count) mastered")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Button("Skip") { next() }.font(.rounded(.subheadline, weight: .semibold))
            }
            if let e = current {
                card(e)
            }
        }
        .onAppear { if current == nil { next() } }
    }

    private func card(_ e: Experiment) -> some View {
        let tint = Playbook.themeTint(e.theme)
        let steps = e.tree
        return VStack(alignment: .leading, spacing: 16) {
            Pill(text: e.theme, symbol: Playbook.themeSymbol(e.theme), tint: tint)
            Text(e.question)
                .font(.serif(.title2, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if revealed == 0 {
                Text("Say the steps in your head first: what would you check, build and compare?")
                    .font(.serif(.body).italic())
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(Array(steps.prefix(revealed).enumerated()), id: \.offset) { i, node in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.rounded(.footnote, weight: .bold))
                        .foregroundStyle(Theme.onTint)
                        .frame(width: 24, height: 24)
                        .background(tint, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.step).font(.serif(.headline, weight: .semibold)).foregroundStyle(Theme.ink)
                        if let id = node.tool, let tool = store.toolsById[id] {
                            Text(tool.name).font(.rounded(.caption, weight: .semibold)).foregroundStyle(Playbook.categoryTint(tool.category))
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if revealed < steps.count {
                Button {
                    withAnimation(.snappy) { revealed += 1 }
                } label: {
                    Label(revealed == 0 ? "Reveal step 1" : "Reveal step \(revealed + 1)", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(tint: tint))
            } else {
                Text(e.chain)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(tint)
                NavigationLink(value: Route.experiment(e.id)) {
                    Label("Open the full map", systemImage: "map").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(tint: tint, secondary: true))
                HStack(spacing: 12) {
                    Button { mark(e, got: false) } label: { Label("Missed", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(FilledButtonStyle(tint: Theme.tint("coral"), secondary: true))
                    Button { mark(e, got: true) } label: { Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(FilledButtonStyle(tint: Theme.tint("lime")))
                }
            }
        }
        .padding(18)
        .card(radius: 20)
    }

    private func mark(_ e: Experiment, got: Bool) {
        var set = mastered
        if got { set.insert(e.id) } else { set.remove(e.id) }
        masteredRaw = set.sorted().joined(separator: ",")
        next()
    }

    /// Unmastered questions first; once all are mastered, anything goes.
    private func next() {
        let pool = experiments.filter { !mastered.contains($0.id) && $0.id != current?.id }
        let fallback = experiments.filter { $0.id != current?.id }
        withAnimation(.snappy) {
            current = (pool.isEmpty ? fallback : pool).randomElement() ?? experiments.first
            revealed = 0
        }
    }
}

// MARK: - Tool match

private struct ToolMatchDrill: View {
    struct Item { let experiment: Experiment; let node: TreeNode; let tool: Tool; let options: [Tool] }

    let playbook: Playbook
    @Environment(ContentStore.self) private var store
    @State private var item: Item?
    @State private var picked: String?
    @State private var score = 0
    @State private var asked = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(asked == 0 ? "Which tool does this step need?" : "\(score) / \(asked) right")
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            if let item {
                let tint = Playbook.themeTint(item.experiment.theme)
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.experiment.question)
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(item.node.step)
                        .font(.serif(.title3, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let how = item.node.how {
                        Text(how).font(.serif(.body)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(item.options) { option in
                        Button { pick(option) } label: {
                            HStack {
                                Text(option.name).font(.rounded(.body, weight: .semibold))
                                Spacer()
                                if picked != nil, option.id == item.tool.id { Image(systemName: "checkmark.circle.fill") }
                                else if picked == option.id { Image(systemName: "xmark.circle.fill") }
                            }
                            .foregroundStyle(color(for: option, in: item))
                            .padding(14)
                            .background(color(for: option, in: item).opacity(picked == nil ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                    }
                    if picked != nil {
                        Text("\(item.tool.name): \(item.tool.what)")
                            .font(.serif(.callout))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { next() } label: { Label("Next", systemImage: "arrow.right").frame(maxWidth: .infinity) }
                            .buttonStyle(FilledButtonStyle(tint: tint))
                    }
                }
                .padding(18)
                .card(radius: 20)
            }
        }
        .onAppear { if item == nil { next() } }
    }

    private func color(for option: Tool, in item: Item) -> Color {
        guard picked != nil else { return Theme.ink }
        if option.id == item.tool.id { return Theme.tint("lime") }
        return picked == option.id ? Theme.tint("coral") : Theme.inkTertiary
    }

    private func pick(_ option: Tool) {
        guard let item else { return }
        picked = option.id
        asked += 1
        if option.id == item.tool.id { score += 1 }
    }

    private func next() {
        // Every node that names a tool, at any depth.
        var pairs: [(Experiment, TreeNode)] = []
        func walk(_ nodes: [TreeNode], _ e: Experiment) {
            for n in nodes {
                if n.tool != nil, n.how != nil { pairs.append((e, n)) }
                for b in n.branches ?? [] { walk(b.then, e) }
            }
        }
        for e in playbook.experiments { walk(e.tree, e) }
        guard let (e, node) = pairs.randomElement(), let tool = node.tool.flatMap({ store.toolsById[$0] }) else { return }
        // Distractors: other tools used somewhere in the maps, so every option is plausible.
        let used = Set(pairs.compactMap(\.1.tool)).subtracting([tool.id]).compactMap { store.toolsById[$0] }
        let options = (Array(used.shuffled().prefix(3)) + [tool]).shuffled()
        withAnimation(.snappy) {
            item = Item(experiment: e, node: node, tool: tool, options: options)
            picked = nil
        }
    }
}
