import SwiftUI

/// An explorable map of how glossary words connect: the chosen word in the middle, its related words
/// around it, and their neighbours further out. Tap any word to walk the map.
struct ConceptMapView: View {
    @Environment(ContentStore.self) private var store
    @State private var centerId: String
    @State private var history: [String] = []

    init(termId: String) {
        _centerId = State(initialValue: termId)
    }

    private struct Node: Identifiable {
        let id: String
        let ring: Int
        let position: CGPoint
        let parent: String?
    }

    var body: some View {
        let center = store.terms[centerId]
        GeometryReader { geo in
            let nodes = layout(in: geo.size)
            let byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            ZStack {
                Canvas { context, _ in
                    for node in nodes {
                        guard let parentId = node.parent, let parent = byId[parentId] else { continue }
                        var path = Path()
                        path.move(to: parent.position)
                        // Gentle curves read better than straight spokes.
                        let mid = CGPoint(x: (parent.position.x + node.position.x) / 2, y: (parent.position.y + node.position.y) / 2)
                        let control = CGPoint(x: mid.x + (geo.size.width / 2 - mid.x) * 0.15, y: mid.y + (geo.size.height / 2 - mid.y) * 0.15)
                        path.addQuadCurve(to: node.position, control: control)
                        let tint = store.terms[node.id].map { Theme.categoryTint($0.category) } ?? Theme.inkTertiary
                        context.stroke(path, with: .color(tint.opacity(node.ring == 1 ? 0.45 : 0.22)), lineWidth: node.ring == 1 ? 2 : 1.2)
                    }
                }
                ForEach(nodes) { node in
                    if let term = store.terms[node.id] {
                        MapNode(term: term, ring: node.ring)
                            .position(node.position)
                            .onTapGesture { recenter(on: node.id) }
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: centerId)
        }
        .padding(.bottom, 4)
        .safeAreaInset(edge: .bottom) {
            if let center { detailCard(center) }
        }
        .background(
            RadialGradient(colors: [Theme.categoryTint(center?.category ?? "").opacity(0.12), Theme.background], center: .center, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
        )
        .navigationTitle("Concept map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let previous = history.popLast() {
                        withAnimation { centerId = previous }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(history.isEmpty)
                .accessibilityLabel("Back to previous word")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { recenter(on: store.glossary.randomElement()?.id ?? centerId) } label: { Image(systemName: "shuffle") }
                    .accessibilityLabel("Random word")
            }
        }
    }

    private func detailCard(_ term: Term) -> some View {
        let tint = Theme.categoryTint(term.category)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Pill(text: term.category, tint: tint)
                Spacer()
                Text("\(store.relatedTermIds(term.id).count) connections")
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Text(term.term).font(.serif(.title3, weight: .bold)).foregroundStyle(Theme.ink)
            Text(term.short)
                .font(.serif(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: Route.term(term.id)) {
                Label("Open in glossary", systemImage: "character.book.closed")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: term.id)
    }

    private func recenter(on id: String) {
        guard id != centerId else { return }
        history.append(centerId)
        if history.count > 30 { history.removeFirst() }
        centerId = id
    }

    /// Centre, up to 8 neighbours on an inner ellipse and a few of their neighbours outside,
    /// then nudged apart so no two labels overlap.
    private func layout(in size: CGSize) -> [Node] {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        var ids = [centerId]
        var rings = [0]
        var parents: [String?] = [nil]
        var targets = [mid]
        let inner = Array(store.relatedTermIds(centerId).prefix(8))
        var used = Set([centerId] + inner)
        let r1 = CGSize(width: size.width * 0.30, height: min(size.height * 0.25, size.width * 0.45))
        let r2 = CGSize(width: size.width * 0.38, height: size.height * 0.42)
        // A stable rotation per word so the map doesn't always start at 12 o'clock.
        let spin = Double(stableHash(centerId) % 360) * .pi / 180
        var outerCount = 0
        for (i, id) in inner.enumerated() {
            let angle = spin + 2 * .pi * Double(i) / Double(max(inner.count, 1))
            ids.append(id); rings.append(1); parents.append(centerId); targets.append(point(mid, r1, angle))
            let perParent = inner.count > 5 ? 1 : 2
            for (j, child) in store.relatedTermIds(id).filter({ !used.contains($0) }).prefix(perParent).enumerated() where outerCount < 9 {
                used.insert(child)
                outerCount += 1
                let spread = perParent == 1 ? 0 : (j == 0 ? -0.3 : 0.3)
                ids.append(child); rings.append(2); parents.append(id); targets.append(point(mid, r2, angle + spread))
            }
        }

        // Relax: push overlapping labels apart, pull gently back towards their place on the rings.
        let sizes = ids.indices.map { MapNode.estimatedSize(store.terms[ids[$0]], ring: rings[$0]) }
        var pos = targets
        let gap: CGFloat = 6
        for _ in 0..<160 {
            for a in pos.indices {
                for b in pos.indices where b > a {
                    let dx = pos[b].x - pos[a].x, dy = pos[b].y - pos[a].y
                    let ox = (sizes[a].width + sizes[b].width) / 2 + gap - abs(dx)
                    let oy = (sizes[a].height + sizes[b].height) / 2 + gap - abs(dy)
                    guard ox > 0, oy > 0 else { continue }
                    // Separate along the cheaper axis; the centre word never moves.
                    let wa: CGFloat = a == 0 ? 0 : (b == 0 ? 1 : 0.5)
                    let wb: CGFloat = 1 - wa
                    if oy < ox {
                        let push = oy * (dy >= 0 ? 1 : -1)
                        pos[a].y -= push * wa; pos[b].y += push * wb
                    } else {
                        let push = ox * (dx >= 0 ? 1 : -1)
                        pos[a].x -= push * wa; pos[b].x += push * wb
                    }
                }
            }
            for i in pos.indices where i > 0 {
                pos[i].x += (targets[i].x - pos[i].x) * 0.04
                pos[i].y += (targets[i].y - pos[i].y) * 0.04
                pos[i].x = min(max(pos[i].x, sizes[i].width / 2 + 4), size.width - sizes[i].width / 2 - 4)
                pos[i].y = min(max(pos[i].y, sizes[i].height / 2 + 4), size.height - sizes[i].height / 2 - 4)
            }
        }
        return ids.indices.map { Node(id: ids[$0], ring: rings[$0], position: pos[$0], parent: parents[$0]) }
    }

    private func point(_ c: CGPoint, _ r: CGSize, _ angle: Double) -> CGPoint {
        CGPoint(x: c.x + r.width * cos(angle), y: c.y + r.height * sin(angle))
    }
}

private struct MapNode: View {
    let term: Term
    let ring: Int

    var body: some View {
        let tint = Theme.categoryTint(term.category)
        Text(label)
            .font(ring == 0 ? .serif(.headline, weight: .bold) : (ring == 1 ? .rounded(.caption, weight: .semibold) : .rounded(.caption2, weight: .medium)))
            .foregroundStyle(ring == 0 ? Theme.onTint : (ring == 1 ? Theme.ink : Theme.inkSecondary))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: Self.maxWidth(ring: ring))
            .padding(.horizontal, ring == 0 ? 14 : 9)
            .padding(.vertical, ring == 0 ? 10 : 6)
            .background(ring == 0 ? tint : (ring == 1 ? Theme.surface : Theme.surface.opacity(0.85)), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(ring == 0 ? 0 : (ring == 1 ? 0.6 : 0.3)), lineWidth: ring == 1 ? 1.5 : 1))
            .shadow(color: (ring == 0 ? tint : .black).opacity(ring == 0 ? 0.35 : 0.06), radius: ring == 0 ? 12 : 4, y: 3)
            .contentShape(Capsule())
            .accessibilityLabel(term.term)
            .accessibilityAddTraits(.isButton)
    }

    /// Short names fit the map better: prefer a compact acronym.
    private var label: String { Self.label(term, ring: ring) }

    static func label(_ term: Term, ring: Int) -> String {
        if ring > 0, term.term.count > 22, let short = term.aka.first(where: { $0.count <= 8 }) { return short }
        return term.term
    }

    static func maxWidth(ring: Int) -> CGFloat { ring == 0 ? 150 : (ring == 1 ? 118 : 96) }

    /// Rendered size of a node, measured with the same fonts, for the overlap-free layout.
    static func estimatedSize(_ term: Term?, ring: Int) -> CGSize {
        guard let term else { return .zero }
        let style: UIFont.TextStyle = ring == 0 ? .headline : (ring == 1 ? .caption1 : .caption2)
        let base = UIFont.preferredFont(forTextStyle: style)
        let font = UIFont(descriptor: base.fontDescriptor.withDesign(ring == 0 ? .serif : .rounded) ?? base.fontDescriptor, size: base.pointSize + (ring == 0 ? 0 : 0.5))
        let box = (label(term, ring: ring) as NSString).boundingRect(
            with: CGSize(width: maxWidth(ring: ring), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil)
        let height = min(box.height, font.lineHeight * 2)
        let padH: CGFloat = ring == 0 ? 14 : 9, padV: CGFloat = ring == 0 ? 10 : 6
        return CGSize(width: ceil(box.width) + padH * 2 + 2, height: ceil(height) + padV * 2)
    }
}
