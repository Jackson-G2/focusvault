import SwiftUI
import UniformTypeIdentifiers


enum DashboardWidgetKind: String, CaseIterable, Codable, Identifiable {
    case intention
    case taskClock
    case youtubeProtection
    case shortFormProtection
    case localTools
    case sleepCalculator
    case learningGuide
    case rhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intention: return "Protecting"
        case .taskClock: return "Task clock"
        case .youtubeProtection: return "YouTube"
        case .shortFormProtection: return "Short-form"
        case .localTools: return "Tools"
        case .sleepCalculator: return "Sleep"
        case .learningGuide: return "Learn next"
        case .rhythm: return "Rhythm"
        }
    }

    var minimumSpan: DashboardWidgetSpan {
        switch self {
        case .intention: return DashboardWidgetSpan(width: 2, height: 1)
        case .taskClock: return DashboardWidgetSpan(width: 2, height: 2)
        case .youtubeProtection: return DashboardWidgetSpan(width: 2, height: 2)
        case .shortFormProtection: return DashboardWidgetSpan(width: 2, height: 1)
        case .localTools: return DashboardWidgetSpan(width: 2, height: 2)
        case .sleepCalculator: return DashboardWidgetSpan(width: 2, height: 1)
        case .learningGuide: return DashboardWidgetSpan(width: 2, height: 1)
        case .rhythm: return DashboardWidgetSpan(width: 2, height: 2)
        }
    }

    var defaultPlacement: DashboardWidgetPlacement {
        switch self {
        case .intention:
            return DashboardWidgetPlacement(kind: self, column: 0, row: 0, width: 4, height: 1)
        case .taskClock:
            return DashboardWidgetPlacement(kind: self, column: 0, row: 1, width: 4, height: 2)
        case .youtubeProtection:
            return DashboardWidgetPlacement(kind: self, column: 0, row: 3, width: 2, height: 2)
        case .shortFormProtection:
            return DashboardWidgetPlacement(kind: self, column: 2, row: 3, width: 2, height: 1)
        case .localTools:
            return DashboardWidgetPlacement(kind: self, column: 0, row: 5, width: 2, height: 2)
        case .sleepCalculator:
            return DashboardWidgetPlacement(kind: self, column: 2, row: 4, width: 2, height: 1)
        case .learningGuide:
            return DashboardWidgetPlacement(kind: self, column: 2, row: 5, width: 2, height: 1)
        case .rhythm:
            return DashboardWidgetPlacement(kind: self, column: 2, row: 6, width: 2, height: 2)
        }
    }

    var sizeChoices: [DashboardWidgetSizeChoice] {
        let minimum = minimumSpan
        var choices = [
            DashboardWidgetSizeChoice(name: "Compact", span: minimum),
            DashboardWidgetSizeChoice(
                name: "Wide",
                span: DashboardWidgetSpan(width: 4, height: minimum.height)
            ),
            DashboardWidgetSizeChoice(
                name: "Tall",
                span: DashboardWidgetSpan(width: minimum.width, height: min(4, minimum.height + 1))
            ),
            DashboardWidgetSizeChoice(
                name: "Large",
                span: DashboardWidgetSpan(width: 4, height: min(4, minimum.height + 1))
            )
        ]
        var seen = Set<DashboardWidgetSpan>()
        choices = choices.filter { seen.insert($0.span).inserted }
        return choices
    }
}

struct DashboardWidgetSpan: Codable, Equatable, Hashable {
    var width: Int
    var height: Int
}

struct DashboardWidgetSizeChoice: Identifiable, Equatable {
    let name: String
    let span: DashboardWidgetSpan
    var id: String { "\(name)-\(span.width)x\(span.height)" }
}

struct DashboardWidgetPlacement: Codable, Equatable, Identifiable {
    let kind: DashboardWidgetKind
    var column: Int
    var row: Int
    var width: Int
    var height: Int

    var id: DashboardWidgetKind { kind }
    var span: DashboardWidgetSpan {
        get { DashboardWidgetSpan(width: width, height: height) }
        set {
            width = newValue.width
            height = newValue.height
        }
    }

    fileprivate var maximumColumn: Int { column + width }
    fileprivate var maximumRow: Int { row + height }

    fileprivate func intersects(_ other: DashboardWidgetPlacement) -> Bool {
        column < other.maximumColumn
            && maximumColumn > other.column
            && row < other.maximumRow
            && maximumRow > other.row
    }
}

private struct DashboardLayoutFile: Codable {
    let version: Int
    let placements: [DashboardWidgetPlacement]
}

final class DashboardLayoutModel: ObservableObject {
    static let columnCount = 4
    static let maximumRows = 40

    @Published private(set) var placements: [DashboardWidgetPlacement]
    @Published var isEditing = false

    var order: [DashboardWidgetKind] {
        placements
            .sorted(by: Self.readingOrder)
            .map(\.kind)
    }

    var occupiedRows: Int {
        placements.map(\.maximumRow).max() ?? 1
    }

    private let defaults: UserDefaults
    private let key: String
    private let legacyKey: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "Vaulty.dashboardCanvas.v3",
        legacyKey: String = "Vaulty.dashboardWidgetOrder"
    ) {
        self.defaults = defaults
        self.key = key
        self.legacyKey = legacyKey

        if let data = defaults.data(forKey: key),
           let file = try? JSONDecoder().decode(DashboardLayoutFile.self, from: data),
           file.version == 3 {
            placements = Self.restore(file.placements)
        } else if let legacyOrder = Self.legacyOrder(defaults.stringArray(forKey: legacyKey)) {
            placements = Self.layoutLegacyOrder(legacyOrder)
        } else {
            placements = DashboardWidgetKind.allCases.map(\.defaultPlacement)
        }
        normalizeAndPersist()
    }

    func placement(for kind: DashboardWidgetKind) -> DashboardWidgetPlacement {
        placements.first(where: { $0.kind == kind }) ?? kind.defaultPlacement
    }

    func move(_ kind: DashboardWidgetKind, toColumn rawColumn: Int, row rawRow: Int) {
        guard let index = placements.firstIndex(where: { $0.kind == kind }) else { return }
        var updated = placements[index]
        updated.column = min(max(0, rawColumn), Self.columnCount - updated.width)
        updated.row = min(max(0, rawRow), Self.maximumRows - updated.height)
        placements[index] = updated
        resolveCollisions(anchored: kind)
        persist()
    }

    func nudge(_ kind: DashboardWidgetKind, columns: Int, rows: Int) {
        let current = placement(for: kind)
        move(kind, toColumn: current.column + columns, row: current.row + rows)
    }

    func resize(_ kind: DashboardWidgetKind, width rawWidth: Int, height rawHeight: Int) {
        guard let index = placements.firstIndex(where: { $0.kind == kind }) else { return }
        let minimum = kind.minimumSpan
        let width = min(Self.columnCount, max(minimum.width, rawWidth))
        let height = min(4, max(minimum.height, rawHeight))
        placements[index].width = width
        placements[index].height = height
        placements[index].column = min(placements[index].column, Self.columnCount - width)
        placements[index].row = min(placements[index].row, Self.maximumRows - height)
        resolveCollisions(anchored: kind)
        persist()
    }

    func apply(_ choice: DashboardWidgetSizeChoice, to kind: DashboardWidgetKind) {
        resize(kind, width: choice.span.width, height: choice.span.height)
    }

    func cycleSize(of kind: DashboardWidgetKind) {
        let choices = kind.sizeChoices
        guard !choices.isEmpty else { return }
        let current = placement(for: kind).span
        let currentIndex = choices.firstIndex(where: { $0.span == current }) ?? -1
        let next = choices[(currentIndex + 1) % choices.count]
        apply(next, to: kind)
    }

    func reset() {
        placements = DashboardWidgetKind.allCases.map(\.defaultPlacement)
        persist()
    }

    private func resolveCollisions(anchored kind: DashboardWidgetKind) {
        guard let anchor = placements.first(where: { $0.kind == kind }) else { return }
        var occupied = [anchor]
        let others = placements
            .filter { $0.kind != kind }
            .sorted(by: Self.readingOrder)
        var resolved = [anchor]

        for var candidate in others {
            candidate.column = min(max(0, candidate.column), Self.columnCount - candidate.width)
            while occupied.contains(where: { candidate.intersects($0) }),
                  candidate.maximumRow < Self.maximumRows {
                candidate.row += 1
            }
            occupied.append(candidate)
            resolved.append(candidate)
        }
        placements = resolved.sorted(by: Self.readingOrder)
    }

    private func normalizeAndPersist() {
        placements = Self.restore(placements)
        var normalized: [DashboardWidgetPlacement] = []
        for var placement in placements.sorted(by: Self.readingOrder) {
            let minimum = placement.kind.minimumSpan
            placement.width = min(Self.columnCount, max(minimum.width, placement.width))
            placement.height = min(4, max(minimum.height, placement.height))
            placement.column = min(max(0, placement.column), Self.columnCount - placement.width)
            placement.row = min(max(0, placement.row), Self.maximumRows - placement.height)
            while normalized.contains(where: { placement.intersects($0) }),
                  placement.maximumRow < Self.maximumRows {
                placement.row += 1
            }
            normalized.append(placement)
        }
        placements = normalized.sorted(by: Self.readingOrder)
        persist()
    }

    private func persist() {
        let file = DashboardLayoutFile(version: 3, placements: placements)
        guard let data = try? JSONEncoder().encode(file) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    private static func restore(_ stored: [DashboardWidgetPlacement]) -> [DashboardWidgetPlacement] {
        var seen = Set<DashboardWidgetKind>()
        var result = stored.filter { seen.insert($0.kind).inserted }
        for kind in DashboardWidgetKind.allCases where seen.insert(kind).inserted {
            var placement = kind.defaultPlacement
            while result.contains(where: { placement.intersects($0) }) {
                placement.row += 1
            }
            result.append(placement)
        }
        return result
    }

    private static func legacyOrder(_ raw: [String]?) -> [DashboardWidgetKind]? {
        guard let raw, !raw.isEmpty else { return nil }
        var seen = Set<DashboardWidgetKind>()
        var result = raw.compactMap(DashboardWidgetKind.init(rawValue:))
            .filter { seen.insert($0).inserted }
        for kind in DashboardWidgetKind.allCases where seen.insert(kind).inserted {
            result.append(kind)
        }
        return result
    }

    private static func layoutLegacyOrder(_ kinds: [DashboardWidgetKind]) -> [DashboardWidgetPlacement] {
        var result: [DashboardWidgetPlacement] = []
        for kind in kinds {
            var candidate = kind.defaultPlacement
            candidate.row = 0
            candidate.column = 0
            var found = false
            for row in 0..<Self.maximumRows where !found {
                for column in 0...(Self.columnCount - candidate.width) {
                    candidate.row = row
                    candidate.column = column
                    if !result.contains(where: { candidate.intersects($0) }) {
                        result.append(candidate)
                        found = true
                        break
                    }
                }
            }
        }
        return result.sorted(by: readingOrder)
    }

    private static func readingOrder(
        _ left: DashboardWidgetPlacement,
        _ right: DashboardWidgetPlacement
    ) -> Bool {
        left.row == right.row ? left.column < right.column : left.row < right.row
    }
}

private struct DashboardPlacementKey: LayoutValueKey {
    static let defaultValue = DashboardWidgetKind.intention.defaultPlacement
}

private extension View {
    func dashboardPlacement(_ placement: DashboardWidgetPlacement) -> some View {
        layoutValue(key: DashboardPlacementKey.self, value: placement)
    }
}

struct DashboardCanvasLayout: Layout {
    static let spacing: CGFloat = 18
    static let rowHeight: CGFloat = 170
    var isEditing = false

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(700, proposal.width ?? 960)
        let occupiedRows = max(1, subviews.map { $0[DashboardPlacementKey.self].maximumRow }.max() ?? 1)
        let rows = isEditing ? max(8, occupiedRows + 1) : occupiedRows
        return CGSize(
            width: width,
            height: CGFloat(rows) * Self.rowHeight + CGFloat(max(0, rows - 1)) * Self.spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columnWidth = (bounds.width - Self.spacing * CGFloat(DashboardLayoutModel.columnCount - 1))
            / CGFloat(DashboardLayoutModel.columnCount)
        for subview in subviews {
            let placement = subview[DashboardPlacementKey.self]
            let rect = Self.rect(
                for: placement,
                columnWidth: columnWidth,
                origin: bounds.origin
            )
            subview.place(
                at: rect.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: rect.width, height: rect.height)
            )
        }
    }

    static func rect(
        for placement: DashboardWidgetPlacement,
        columnWidth: CGFloat,
        origin: CGPoint = .zero
    ) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(placement.column) * (columnWidth + spacing),
            y: origin.y + CGFloat(placement.row) * (rowHeight + spacing),
            width: CGFloat(placement.width) * columnWidth + CGFloat(placement.width - 1) * spacing,
            height: CGFloat(placement.height) * rowHeight + CGFloat(placement.height - 1) * spacing
        )
    }
}

struct DashboardWidgetCanvas<Content: View>: View {
    @ObservedObject var model: DashboardLayoutModel
    @Binding var draggedWidget: DashboardWidgetKind?
    let reduceMotion: Bool
    @ViewBuilder let content: (DashboardWidgetKind) -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isEditing {
                DashboardGridBackground(model: model)
                    .allowsHitTesting(false)
            }

            DashboardCanvasLayout(isEditing: model.isEditing) {
                ForEach(model.order) { kind in
                    let placement = model.placement(for: kind)
                    DashboardDraggableWidget(
                        placement: placement,
                        isEditing: model.isEditing,
                        reduceMotion: reduceMotion,
                        dragged: $draggedWidget,
                        layoutModel: model
                    ) {
                        content(kind)
                    }
                    .dashboardPlacement(placement)
                }
            }

            if model.isEditing, draggedWidget != nil {
                DashboardDropOverlay(
                    model: model,
                    draggedWidget: $draggedWidget
                )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
            value: model.placements
        )
    }
}

private struct DashboardGridBackground: View {
    @ObservedObject var model: DashboardLayoutModel

    var body: some View {
        GeometryReader { proxy in
            let spacing = DashboardCanvasLayout.spacing
            let columnWidth = (proxy.size.width - spacing * CGFloat(DashboardLayoutModel.columnCount - 1))
                / CGFloat(DashboardLayoutModel.columnCount)
            let rows = max(8, min(DashboardLayoutModel.maximumRows, model.occupiedRows + 1))

            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<DashboardLayoutModel.columnCount, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Tideglass.line.opacity(row < model.occupiedRows ? 0.48 : 0.25),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 7])
                            )
                            .frame(width: columnWidth, height: DashboardCanvasLayout.rowHeight)
                            .offset(
                                x: CGFloat(column) * (columnWidth + spacing),
                                y: CGFloat(row) * (DashboardCanvasLayout.rowHeight + spacing)
                            )
                    }
                }
            }
        }
    }
}

private struct DashboardDropOverlay: View {
    @ObservedObject var model: DashboardLayoutModel
    @Binding var draggedWidget: DashboardWidgetKind?

    var body: some View {
        GeometryReader { proxy in
            let spacing = DashboardCanvasLayout.spacing
            let columnWidth = (proxy.size.width - spacing * CGFloat(DashboardLayoutModel.columnCount - 1))
                / CGFloat(DashboardLayoutModel.columnCount)
            let rows = max(8, min(DashboardLayoutModel.maximumRows, model.occupiedRows + 1))

            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<DashboardLayoutModel.columnCount, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.001))
                            .frame(width: columnWidth, height: DashboardCanvasLayout.rowHeight)
                            .offset(
                                x: CGFloat(column) * (columnWidth + spacing),
                                y: CGFloat(row) * (DashboardCanvasLayout.rowHeight + spacing)
                            )
                            .onDrop(
                                of: [UTType.text],
                                delegate: DashboardCellDropDelegate(
                                    column: column,
                                    row: row,
                                    dragged: $draggedWidget,
                                    model: model
                                )
                            )
                    }
                }
            }
        }
    }
}

private struct DashboardCellDropDelegate: DropDelegate {
    let column: Int
    let row: Int
    @Binding var dragged: DashboardWidgetKind?
    let model: DashboardLayoutModel

    func dropEntered(info: DropInfo) {
        guard let dragged else { return }
        let placement = model.placement(for: dragged)
        let centeredColumn = column - max(0, placement.width / 2)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
            model.move(dragged, toColumn: centeredColumn, row: row)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct DashboardDraggableWidget<Content: View>: View {
    let placement: DashboardWidgetPlacement
    let isEditing: Bool
    let reduceMotion: Bool
    @Binding var dragged: DashboardWidgetKind?
    let layoutModel: DashboardLayoutModel
    @ViewBuilder let content: () -> Content

    @State private var jiggle = false
    @State private var resizeOrigin: DashboardWidgetSpan?

    private var kind: DashboardWidgetKind { placement.kind }

    var body: some View {
        GeometryReader { proxy in
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isEditing { editBar }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isEditing { resizeHandle(in: proxy.size) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Tideglass.signal.opacity(0.55), lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .rotationEffect(
                    isEditing && !reduceMotion
                        ? .degrees(jiggle ? 0.22 : -0.22)
                        : .zero
                )
                .scaleEffect(dragged == kind ? 0.97 : 1)
                .opacity(dragged == kind ? 0.66 : 1)
                .animation(.easeInOut(duration: 0.14), value: dragged)
        }
        .onAppear { updateJiggle() }
        .onChange(of: isEditing) { _ in updateJiggle() }
    }

    private var editBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal")
                Text(kind.title)
            }
            .contentShape(Capsule())
            .onDrag {
                dragged = kind
                return NSItemProvider(object: kind.rawValue as NSString)
            }
            .accessibilityLabel("Move \(kind.title) widget")
            .accessibilityIdentifier("move-widget-\(kind.rawValue)")

            Menu {
                Section("Size") {
                    ForEach(kind.sizeChoices) { choice in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                layoutModel.apply(choice, to: kind)
                            }
                        } label: {
                            Label(
                                "\(choice.name) · \(choice.span.width)×\(choice.span.height)",
                                systemImage: placement.span == choice.span ? "checkmark" : "rectangle.resize"
                            )
                        }
                    }
                }
                Section("Position") {
                    Button("Move left") { layoutModel.nudge(kind, columns: -1, rows: 0) }
                    Button("Move right") { layoutModel.nudge(kind, columns: 1, rows: 0) }
                    Button("Move up") { layoutModel.nudge(kind, columns: 0, rows: -1) }
                    Button("Move down") { layoutModel.nudge(kind, columns: 0, rows: 1) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Resize or move \(kind.title)")
            .accessibilityIdentifier("widget-menu-\(kind.rawValue)")
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(Tideglass.canvas)
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(Tideglass.signal.opacity(0.96), in: Capsule())
        .padding(8)
    }

    private func resizeHandle(in size: CGSize) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                layoutModel.cycleSize(of: kind)
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tideglass.canvas)
                .frame(width: 30, height: 30)
                .background(Tideglass.signal.opacity(0.96), in: Circle())
                .padding(8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let origin = resizeOrigin ?? placement.span
                    if resizeOrigin == nil { resizeOrigin = origin }
                    let approximateColumn = max(1, size.width / CGFloat(max(1, placement.width)))
                    let approximateRow = max(1, size.height / CGFloat(max(1, placement.height)))
                    let widthDelta = Int((value.translation.width / approximateColumn).rounded())
                    let heightDelta = Int((value.translation.height / approximateRow).rounded())
                    layoutModel.resize(
                        kind,
                        width: origin.width + widthDelta,
                        height: origin.height + heightDelta
                    )
                }
                .onEnded { _ in resizeOrigin = nil }
        )
        .help("Drag to resize \(kind.title), or click for the next size")
        .accessibilityLabel("Resize \(kind.title) widget")
        .accessibilityValue("\(placement.width) columns by \(placement.height) rows")
        .accessibilityIdentifier("resize-widget-\(kind.rawValue)")
    }

    private func updateJiggle() {
        guard isEditing, !reduceMotion else {
            jiggle = false
            return
        }
        jiggle = false
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
            jiggle = true
        }
    }
}
