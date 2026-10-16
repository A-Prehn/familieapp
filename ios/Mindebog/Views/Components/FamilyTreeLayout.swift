import Foundation
import CoreGraphics

// Beregner, hvor hver person skal stå i familietræet — uden at tegne noget.
//
// En "enhed" er én person (ankeret) med sine partnere ved siden af. Børn hænger under
// det par, de hører til: fælles børn under parret, et barn med kun ankeret som forælder
// under ankeret alene, og et barn, der kun er partnerens (sammenbragt), under parret
// med en stiplet linje. Så kan halvsøskende og sammenbragte familier vises rigtigt.
//
// Hver person placeres kun én gang (visited), så en cyklus eller en fejlindtastning
// aldrig kan få træet til at løbe i ring.
struct FamilyTreeLayout {
    struct Node: Identifiable {
        let person: Person
        var frame: CGRect
        var id: String { person.id }
    }
    struct Line: Identifiable {
        let id = UUID()
        var points: [CGPoint]
        var dashed = false
    }

    static let nodeWidth: CGFloat = 92
    static let nodeHeight: CGFloat = 118
    static let hGap: CGFloat = 14         // mellem søskende
    static let coupleGap: CGFloat = 10    // mellem partnere
    static let vGap: CGFloat = 56         // mellem generationer

    private(set) var nodes: [Node] = []
    private(set) var lines: [Line] = []
    private(set) var size: CGSize = .zero

    private let byId: [String: Person]
    private var visited: Set<String> = []

    init(persons: [Person]) {
        byId = Dictionary(persons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = Set(byId.keys)

        // Rødder: personer uden (kendte) forældre. Ældste først.
        let roots = persons
            .filter { $0.parentIds.allSatisfy { !known.contains($0) } }
            .sorted(by: Self.olderFirst)
        var x: CGFloat = 0
        for root in roots where !visited.contains(root.id) {
            // En rod, der bliver tegnet som partner til en tidligere rod, springes over.
            if roots.contains(where: { other in
                other.id != root.id && Self.olderFirst(other, root)
                    && Self.partners(of: other, in: byId).contains { $0.id == root.id } }) { continue }
            x += place(anchor: root, x: x, y: 0) + Self.hGap * 3
        }
        // Personer, der ikke blev nået (fx forældre-id'er, der peger i ring): stil dem for sig.
        for p in persons.sorted(by: Self.olderFirst) where !visited.contains(p.id) {
            x += place(anchor: p, x: x, y: 0) + Self.hGap * 3
        }
        let height = nodes.map(\.frame.maxY).max() ?? 0
        size = CGSize(width: max(0, x - Self.hGap * 3), height: height)
    }

    // MARK: - Hjælpere

    private static func partners(of p: Person, in byId: [String: Person]) -> [Person] {
        var ids = p.partnerIds
        // Også dem, der har p som partner, selv om det kun er sat den ene vej.
        for other in byId.values where other.partnerIds.contains(p.id) && !ids.contains(other.id) {
            ids.append(other.id)
        }
        return ids.compactMap { byId[$0] }
    }

    static func olderFirst(_ a: Person, _ b: Person) -> Bool {
        switch (a.birthDate, b.birthDate) {
        case let (x?, y?): return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.name < b.name
        }
    }

    private struct Group {
        var children: [Person]
        /// Indeks i rækken for de to i parret — nil = ankerets egne børn.
        var pair: (Int, Int)?
    }

    // MARK: - Placering

    /// Placerer ankeret + partnere på række ved (x, y) og deres børn nedenunder.
    /// Returnerer den samlede bredde, som undertræet optager.
    private mutating func place(anchor: Person, x: CGFloat, y: CGFloat) -> CGFloat {
        visited.insert(anchor.id)
        // Partnere, der ikke selv hænger under nogen i træet, stilles ved siden af ankeret.
        let partners = Self.partners(of: anchor, in: byId).filter { p in
            !visited.contains(p.id) && p.parentIds.allSatisfy { byId[$0] == nil }
        }
        partners.forEach { visited.insert($0.id) }

        // Rækken: første partner til venstre, ankeret, resten til højre.
        var row: [Person] = []
        if let first = partners.first { row.append(first) }
        row.append(anchor)
        row.append(contentsOf: partners.dropFirst())
        let anchorIndex = row.firstIndex { $0.id == anchor.id } ?? 0
        let rowWidth = CGFloat(row.count) * Self.nodeWidth + CGFloat(row.count - 1) * Self.coupleGap

        // Børnegrupper i rækkens rækkefølge: pr. partner (fælles + sammenbragte) og ankerets egne.
        let partnerIds = Set(row.map(\.id)).subtracting([anchor.id])
        func take(_ belongs: (Person) -> Bool) -> [Person] {
            let kids = byId.values
                .filter { !visited.contains($0.id) && belongs($0) }
                .sorted(by: Self.olderFirst)
            kids.forEach { visited.insert($0.id) }
            return kids
        }
        var groups: [Group] = []
        for (i, p) in row.enumerated() {
            if i == anchorIndex {
                // Ankerets egne børn: dem, der ikke har nogen af partnerne i rækken som forælder.
                groups.append(Group(children: take { c in
                    c.parentIds.contains(anchor.id) && !c.parentIds.contains(where: partnerIds.contains)
                }, pair: nil))
            } else {
                // Fælles børn og partnerens egne (sammenbragte) børn.
                groups.append(Group(children: take { $0.parentIds.contains(p.id) },
                                    pair: (min(i, anchorIndex), max(i, anchorIndex))))
            }
        }

        // Børnene lægges ud først for at kende bredden.
        let childY = y + Self.nodeHeight + Self.vGap
        let firstNode = nodes.count, firstLine = lines.count
        var cursor = x
        var spans: [(group: Group, frames: [CGRect])] = []
        for g in groups where !g.children.isEmpty {
            var frames: [CGRect] = []
            for c in g.children {
                let before = nodes.count
                let w = place(anchor: c, x: cursor, y: childY)
                // Barnets egen node er den første, der blev tilføjet i kaldet — find den på id.
                if let f = nodes[before...].first(where: { $0.person.id == c.id })?.frame { frames.append(f) }
                cursor += w + Self.hGap
            }
            spans.append((g, frames))
            cursor += Self.hGap   // lidt ekstra luft mellem grupper
        }
        var childrenWidth: CGFloat = 0
        if !spans.isEmpty {
            cursor -= Self.hGap * 2
            childrenWidth = cursor - x
        }

        // Centrér: rækken over børnene, eller børnene under rækken, alt efter hvad der er bredest.
        let total = max(rowWidth, childrenWidth)
        let rowX = x + (total - rowWidth) / 2
        let shift = (total - childrenWidth) / 2
        if shift > 0, !spans.isEmpty {
            for i in firstNode..<nodes.count { nodes[i].frame.origin.x += shift }
            for i in firstLine..<lines.count {
                lines[i].points = lines[i].points.map { CGPoint(x: $0.x + shift, y: $0.y) }
            }
            spans = spans.map { ($0.group, $0.frames.map { $0.offsetBy(dx: shift, dy: 0) }) }
        }

        // Noder i rækken
        var rowFrames: [CGRect] = []
        for (i, p) in row.enumerated() {
            let frame = CGRect(x: rowX + CGFloat(i) * (Self.nodeWidth + Self.coupleGap), y: y,
                               width: Self.nodeWidth, height: Self.nodeHeight)
            nodes.append(Node(person: p, frame: frame))
            rowFrames.append(frame)
        }
        // Partnerlinjer mellem naboer i rækken, i højde med cirklens midte.
        let circleMidY = y + Self.nodeWidth * 0.3
        for i in 0..<(row.count - 1) {
            lines.append(Line(points: [CGPoint(x: rowFrames[i].maxX, y: circleMidY),
                                       CGPoint(x: rowFrames[i + 1].minX, y: circleMidY)]))
        }

        // Linjer ned til børnegrupperne
        let busY = childY - Self.vGap / 2
        for (g, frames) in spans {
            let dropX: CGFloat, topY: CGFloat
            if let (l, r) = g.pair {
                dropX = (rowFrames[l].maxX + rowFrames[r].minX) / 2
                topY = circleMidY
            } else {
                dropX = rowFrames[anchorIndex].midX
                topY = rowFrames[anchorIndex].maxY
            }
            let mids = frames.map(\.midX)
            let busMin = min(dropX, mids.min() ?? dropX), busMax = max(dropX, mids.max() ?? dropX)
            lines.append(Line(points: [CGPoint(x: dropX, y: topY), CGPoint(x: dropX, y: busY)]))
            if busMax - busMin > 0.5 {
                lines.append(Line(points: [CGPoint(x: busMin, y: busY), CGPoint(x: busMax, y: busY)]))
            }
            let pairIds: Set<String> = g.pair.map { [row[$0.0].id, row[$0.1].id] } ?? [anchor.id]
            for (c, f) in zip(g.children, frames) {
                // Stiplet, når barnet ikke har begge i parret som forældre (halvsøskende/sammenbragt).
                let dashed = g.pair != nil && !pairIds.isSubset(of: Set(c.parentIds))
                lines.append(Line(points: [CGPoint(x: f.midX, y: busY), CGPoint(x: f.midX, y: f.minY)], dashed: dashed))
            }
        }
        return total
    }
}
