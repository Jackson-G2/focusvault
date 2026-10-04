import Foundation
import Combine

private struct DashboardLayoutFile: Codable {
    let version: Int
    let placements: [DashboardWidgetPlacement]
}

final class DashboardLayoutModel: ObservableObject {
    static let columnCount = DashboardPlacementEngine.columnCount
    static let maximumRows = DashboardPlacementEngine.maximumRows

    @Published private(set) var placements: [DashboardWidgetPlacement]
    @Published var isEditing = false

    var order: [DashboardWidgetKind] {
        placements.sorted(by: DashboardPlacementEngine.readingOrder).map(\.kind)
    }
    var occupiedRows: Int { placements.map(\.maximumRow).max() ?? 1 }

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "Vaulty.dashboardCanvas.v3",
        legacyKey: String = "Vaulty.dashboardWidgetOrder"
    ) {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let file = try? JSONDecoder().decode(DashboardLayoutFile.self, from: data),
           file.version == 3 {
            placements = DashboardPlacementEngine.restore(file.placements)
        } else if let order = DashboardPlacementEngine.legacyOrder(defaults.stringArray(forKey: legacyKey)) {
            placements = DashboardPlacementEngine.layoutLegacyOrder(order)
        } else {
            placements = DashboardPlacementEngine.restore(DashboardWidgetKind.allCases.map(\.defaultPlacement))
        }
        persist()
    }

    func placement(for kind: DashboardWidgetKind) -> DashboardWidgetPlacement {
        placements.first { $0.kind == kind } ?? kind.defaultPlacement
    }

    func move(_ kind: DashboardWidgetKind, toColumn column: Int, row: Int) {
        update(kind) { placement in
            placement.column = column
            placement.row = row
        }
    }

    func nudge(_ kind: DashboardWidgetKind, columns: Int, rows: Int) {
        let current = placement(for: kind)
        // Public calls may supply untrusted deltas; saturate instead of trapping.
        let column = current.column.addingReportingOverflow(columns)
        let row = current.row.addingReportingOverflow(rows)
        move(kind,
             toColumn: column.overflow ? (columns > 0 ? Self.columnCount : 0) : column.partialValue,
             row: row.overflow ? (rows > 0 ? Self.maximumRows : 0) : row.partialValue)
    }

    func resize(_ kind: DashboardWidgetKind, width: Int, height: Int) {
        update(kind) { placement in
            placement.width = width
            placement.height = height
        }
    }

    func apply(_ choice: DashboardWidgetSizeChoice, to kind: DashboardWidgetKind) {
        resize(kind, width: choice.span.width, height: choice.span.height)
    }

    func cycleSize(of kind: DashboardWidgetKind) {
        let choices = kind.sizeChoices
        guard !choices.isEmpty else { return }
        let current = placement(for: kind).span
        let index = choices.firstIndex { $0.span == current } ?? -1
        apply(choices[(index + 1) % choices.count], to: kind)
    }

    func reset() {
        let restored = DashboardWidgetKind.allCases.map(\.defaultPlacement)
        guard placements != restored else { return }
        placements = restored
        persist()
    }

    private func update(_ kind: DashboardWidgetKind, mutation: (inout DashboardWidgetPlacement) -> Void) {
        guard let index = placements.firstIndex(where: { $0.kind == kind }) else { return }
        var placement = placements[index]
        mutation(&placement)
        placement = DashboardPlacementEngine.clamp(placement)
        guard placement != placements[index] else { return }
        var updated = placements
        updated[index] = placement
        let resolved = DashboardPlacementEngine.resolve(updated, anchored: kind)
        guard resolved != placements else { return }
        placements = resolved
        persist()
    }

    private func persist() {
        let file = DashboardLayoutFile(version: 3, placements: placements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(file), data != defaults.data(forKey: key) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
