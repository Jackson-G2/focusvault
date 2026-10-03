import SwiftUI
import UniformTypeIdentifiers

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
