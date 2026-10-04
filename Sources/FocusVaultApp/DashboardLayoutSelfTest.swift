import Darwin
import Foundation
import VaultyCore

extension VaultyAppInteractionSelfTest {
    @MainActor
    static func testDashboardWidgetPersistence() throws {
        let suiteName = "VaultyDashboardSelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InteractionTestError.failed("could not create isolated dashboard defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "widget-canvas"
        let layout = DashboardLayoutModel(defaults: defaults, key: key, legacyKey: "legacy-order")
        try checkApp(
            Set(layout.order) == Set(DashboardWidgetKind.allCases),
            "dashboard did not start with every widget"
        )

        layout.move(.localTools, toColumn: 2, row: 10)
        var tools = layout.placement(for: .localTools)
        try checkApp(tools.column == 2 && tools.row == 10, "dashboard widget did not move to an exact slot")

        layout.resize(.localTools, width: 4, height: 3)
        tools = layout.placement(for: .localTools)
        try checkApp(tools.width == 4 && tools.height == 3, "dashboard widget did not resize")
        try checkApp(tools.column == 0, "wide widget was not clamped inside the canvas")
        try checkApp(!hasDashboardOverlap(layout.placements), "dashboard collision resolution left overlapping widgets")

        let beforeCycle = layout.placement(for: .intention).span
        layout.cycleSize(of: .intention)
        try checkApp(
            layout.placement(for: .intention).span != beforeCycle,
            "dashboard resize handle cycle did not change size"
        )
        try checkApp(!hasDashboardOverlap(layout.placements), "size cycling created an overlap")

        let restored = DashboardLayoutModel(defaults: defaults, key: key, legacyKey: "legacy-order")
        try checkApp(
            restored.placement(for: .localTools) == tools,
            "dashboard position and size did not persist"
        )

        defaults.set(
            [DashboardWidgetKind.rhythm.rawValue, DashboardWidgetKind.localTools.rawValue, DashboardWidgetKind.intention.rawValue],
            forKey: "legacy-order"
        )
        let migrated = DashboardLayoutModel(
            defaults: defaults,
            key: "migrated-widget-canvas",
            legacyKey: "legacy-order"
        )
        try checkApp(migrated.order.first == .localTools, "legacy widget order did not migrate")
        try checkApp(!hasDashboardOverlap(migrated.placements), "migrated dashboard contains overlaps")

        struct OldLayout: Encodable {
            let version = 3
            let placements: [DashboardWidgetPlacement]
        }
        var retired = DashboardWidgetKind.rhythm.defaultPlacement
        retired.row = 30
        defaults.set(try JSONEncoder().encode(OldLayout(placements: layout.placements + [retired])), forKey: "retired-rhythm-layout")
        let withoutRhythm = DashboardLayoutModel(defaults: defaults, key: "retired-rhythm-layout", legacyKey: "unused")
        try checkApp(!withoutRhythm.order.contains(.rhythm) && !migrated.order.contains(.rhythm), "Rhythm survived saved-layout migration")
        try checkApp(withoutRhythm.placement(for: .localTools) == tools, "removing Rhythm reset other widget positions")
        try checkApp(!DashboardWidgetKind.allCases.contains(.rhythm), "Rhythm remains available after Reset")
        print("PASS: Rhythm removed from saved/default/legacy layouts without resetting other widgets")

        restored.reset()
        try checkApp(
            restored.placements == DashboardWidgetKind.allCases.map(\.defaultPlacement),
            "dashboard reset did not restore default positions and sizes"
        )
    }

    static func hasDashboardOverlap(_ placements: [DashboardWidgetPlacement]) -> Bool {
        for leftIndex in placements.indices {
            for rightIndex in placements.indices where rightIndex > leftIndex {
                let left = placements[leftIndex]
                let right = placements[rightIndex]
                let overlaps = left.column < right.column + right.width
                    && left.column + left.width > right.column
                    && left.row < right.row + right.height
                    && left.row + left.height > right.row
                if overlaps { return true }
            }
        }
        return false
    }

}
