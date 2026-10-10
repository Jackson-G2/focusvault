import Foundation

/// Pure, bounded placement rules. Persisted coordinates are untrusted input;
/// clamp them before adding dimensions or testing intersections.
enum DashboardPlacementEngine {
    static let columnCount = 4
    static let maximumRows = 40

    static func clamp(_ placement: DashboardWidgetPlacement) -> DashboardWidgetPlacement {
        var result = placement
        let minimum = result.kind.minimumSpan
        result.width = min(columnCount, max(minimum.width, result.width))
        result.height = min(4, max(minimum.height, result.height))
        result.column = min(max(0, result.column), columnCount - result.width)
        result.row = min(max(0, result.row), maximumRows - result.height)
        return result
    }

    static func restore(_ stored: [DashboardWidgetPlacement]) -> [DashboardWidgetPlacement] {
        var seen = Set<DashboardWidgetKind>()
        var result = resolve(stored.filter { $0.kind != .rhythm && seen.insert($0.kind).inserted }.map(clamp))
        for kind in DashboardWidgetKind.allCases where seen.insert(kind).inserted {
            result.append(firstFreePosition(for: kind.defaultPlacement, occupied: result))
        }
        return result.sorted(by: readingOrder)
    }

    static func resolve(
        _ placements: [DashboardWidgetPlacement],
        anchored kind: DashboardWidgetKind? = nil
    ) -> [DashboardWidgetPlacement] {
        let clamped = placements.map(clamp)
        let anchor = clamped.first { $0.kind == kind }
        var occupied = anchor.map { [$0] } ?? []
        let others = clamped.filter { $0.kind != kind }.sorted(by: readingOrder)
        for candidate in others {
            occupied.append(firstFreePosition(for: candidate, occupied: occupied))
        }
        return occupied.sorted(by: readingOrder)
    }

    static func legacyOrder(_ raw: [String]?) -> [DashboardWidgetKind]? {
        guard let raw, !raw.isEmpty else { return nil }
        var seen = Set<DashboardWidgetKind>()
        var result = raw.compactMap(DashboardWidgetKind.init(rawValue:))
            .filter { $0 != .rhythm && seen.insert($0).inserted }
        for kind in DashboardWidgetKind.allCases where seen.insert(kind).inserted { result.append(kind) }
        return result
    }

    static func layoutLegacyOrder(_ kinds: [DashboardWidgetKind]) -> [DashboardWidgetPlacement] {
        var occupied: [DashboardWidgetPlacement] = []
        for kind in kinds {
            var candidate = kind.defaultPlacement
            candidate.column = 0
            candidate.row = 0
            occupied.append(firstFreePosition(for: candidate, occupied: occupied, packColumns: true))
        }
        return occupied.sorted(by: readingOrder)
    }

    static func readingOrder(_ left: DashboardWidgetPlacement, _ right: DashboardWidgetPlacement) -> Bool {
        if left.row != right.row { return left.row < right.row }
        if left.column != right.column { return left.column < right.column }
        return left.kind.rawValue < right.kind.rawValue
    }

    private static func firstFreePosition(
        for placement: DashboardWidgetPlacement,
        occupied: [DashboardWidgetPlacement],
        packColumns: Bool = false
    ) -> DashboardWidgetPlacement {
        var candidate = clamp(placement)
        let lastRow = maximumRows - candidate.height
        // Preserve gaps and positions; move neighbours downward first. If the
        // bottom is full, wrap to earlier free rows instead of leaving overlap.
        let rows = Array(candidate.row...lastRow) + Array(0..<candidate.row)
        let columns = packColumns ? Array(0...(columnCount - candidate.width)) : [candidate.column]
        for row in rows {
            for column in columns {
                candidate.row = row
                candidate.column = column
                if !occupied.contains(where: { candidate.intersects($0) }) { return candidate }
            }
        }
        // Seven supported widgets, each at most four rows, fit in forty rows
        // even at one column. Reaching this indicates a programming error.
        preconditionFailure("Dashboard placement capacity invariant was violated")
    }
}
