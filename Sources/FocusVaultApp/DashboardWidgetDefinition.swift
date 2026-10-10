import Foundation

enum DashboardWidgetKind: String, CaseIterable, Codable, Identifiable {
    case intention
    case taskClock
    case youtubeProtection
    case shortFormProtection
    case localTools
    case sleepCalculator
    case learningGuide
    case gptUsage
    case filesFolders
    case rhythm

    // Keep the retired raw value decodable so existing layouts migrate without
    // resetting the user's remaining widget positions.
    static let allCases: [DashboardWidgetKind] = [
        .intention, .taskClock, .youtubeProtection, .shortFormProtection,
        .localTools, .sleepCalculator, .learningGuide, .gptUsage, .filesFolders
    ]

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
        case .gptUsage: return "GPT usage"
        case .filesFolders: return "Files & Folders"
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
        case .gptUsage: return DashboardWidgetSpan(width: 2, height: 2)
        case .filesFolders: return DashboardWidgetSpan(width: 2, height: 1)
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
        case .gptUsage:
            return DashboardWidgetPlacement(kind: self, column: 2, row: 6, width: 2, height: 2)
        case .filesFolders:
            return DashboardWidgetPlacement(kind: self, column: 0, row: 7, width: 2, height: 1)
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

    var maximumColumn: Int { column + width }
    var maximumRow: Int { row + height }

    func intersects(_ other: DashboardWidgetPlacement) -> Bool {
        column < other.maximumColumn
            && maximumColumn > other.column
            && row < other.maximumRow
            && maximumRow > other.row
    }
}
