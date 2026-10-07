import SwiftUI

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

/// Transient state for the widget currently under the cursor. The dragged
/// widget never mutates the layout mid-drag: it follows the cursor through a
/// visual offset while the grid shows the highlighted drop cell, and the move
/// is committed once, on drop. Layout churn during a live gesture is what
/// makes SwiftUI drags glitch, so the model is only touched at drag end.
struct DashboardWidgetDragState: Equatable {
    let kind: DashboardWidgetKind
    var target: DashboardWidgetPlacement
    var translation: CGSize
}

struct DashboardWidgetCanvas<Content: View>: View {
    @ObservedObject var model: DashboardLayoutModel
    let reduceMotion: Bool
    @ViewBuilder let content: (DashboardWidgetKind) -> Content

    @State private var drag: DashboardWidgetDragState?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isEditing {
                DashboardGridBackground(model: model, drag: drag)
                    .allowsHitTesting(false)
            }

            DashboardCanvasLayout(isEditing: model.isEditing) {
                ForEach(model.order) { kind in
                    let placement = model.placement(for: kind)
                    DashboardDraggableWidget(
                        placement: placement,
                        isEditing: model.isEditing,
                        reduceMotion: reduceMotion,
                        drag: $drag,
                        layoutModel: model
                    ) {
                        content(kind)
                    }
                    .dashboardPlacement(placement)
                }
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
            value: model.placements
        )
        .onChange(of: model.isEditing) { editing in
            if !editing { drag = nil }
        }
    }
}

private struct DashboardGridBackground: View {
    @ObservedObject var model: DashboardLayoutModel
    let drag: DashboardWidgetDragState?

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

                if let drag {
                    let rect = DashboardCanvasLayout.rect(for: drag.target, columnWidth: columnWidth)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Tideglass.signal.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Tideglass.signal.opacity(0.85), lineWidth: 1.5)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}

struct DashboardDraggableWidget<Content: View>: View {
    let placement: DashboardWidgetPlacement
    let isEditing: Bool
    let reduceMotion: Bool
    @Binding var drag: DashboardWidgetDragState?
    let layoutModel: DashboardLayoutModel
    @ViewBuilder let content: () -> Content

    @State private var resizeOrigin: DashboardWidgetSpan?

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var kind: DashboardWidgetKind { placement.kind }
    private var isDragging: Bool { drag?.kind == kind }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipShape(Self.shape)
                    .allowsHitTesting(!isEditing)

                if isEditing {
                    // Transparent surface: in Arrange mode the whole widget is
                    // the drag handle. Grab anywhere, drop on a highlighted cell.
                    Color.clear
                        .contentShape(Self.shape)
                        .highPriorityGesture(moveGesture(in: proxy.size))
                        .help("Drag to move \(kind.title)")
                        .accessibilityLabel("Move \(kind.title) widget")
                        .accessibilityIdentifier("move-widget-\(kind.rawValue)")
                }
            }
            .contentShape(Self.shape)
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    editBar.allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isEditing { resizeHandle(in: proxy.size) }
            }
            .clipShape(Self.shape)
            .overlay {
                if isEditing {
                    Self.shape
                        .strokeBorder(
                            Tideglass.signal.opacity(isDragging ? 0.92 : 0.55),
                            lineWidth: isDragging ? 2 : 1.5
                        )
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: isDragging ? 16 : 0)
            .scaleEffect(isDragging ? 1.02 : 1)
            .offset(isDragging ? (drag?.translation ?? .zero) : .zero)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
                value: isDragging
            )
        }
    }

    /// Direct manipulation. The gesture only records the cursor translation and
    /// computes the target cell from the widget's *fixed* start slot, so nothing
    /// in the layout moves while the mouse button is down. On release the move
    /// commits once and the offset springs to zero over the same curve the
    /// layout animates with, so the widget hands off from cursor to cell.
    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard size.width > 1, size.height > 1 else { return }

                let spacing = DashboardCanvasLayout.spacing
                let columnWidth = (size.width - CGFloat(max(0, placement.width - 1)) * spacing)
                    / CGFloat(max(1, placement.width))
                let rowHeight = (size.height - CGFloat(max(0, placement.height - 1)) * spacing)
                    / CGFloat(max(1, placement.height))

                let originX = CGFloat(placement.column) * (columnWidth + spacing)
                let originY = CGFloat(placement.row) * (rowHeight + spacing)
                let column = Int(((originX + value.translation.width) / (columnWidth + spacing)).rounded())
                let row = Int(((originY + value.translation.height) / (rowHeight + spacing)).rounded())

                var target = placement
                target.column = min(max(0, column), DashboardLayoutModel.columnCount - placement.width)
                target.row = min(max(0, row), DashboardLayoutModel.maximumRows - placement.height)
                drag = DashboardWidgetDragState(
                    kind: kind,
                    target: target,
                    translation: value.translation
                )
            }
            .onEnded { _ in
                guard let state = drag, state.kind == kind else { return }
                drag = nil
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    layoutModel.move(kind, toColumn: state.target.column, row: state.target.row)
                }
            }
    }

    private var editBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            Text(kind.title)
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(Tideglass.canvas)
        .padding(.horizontal, 9)
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
}
