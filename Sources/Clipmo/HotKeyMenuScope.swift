// ホットキーで開く menu の種類を config 名と対応付ける定義です。
import Foundation

enum HotKeyMenuScope: Equatable {
    case all
    case history
    case snippets
    case snippet(Int)
    case transforms
    case builtInTransforms
    case customTransforms

    /// config は人手編集前提なので、大文字小文字や古い typo をここで吸収します。
    init?(configName: String) {
        let normalized = configName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "all":
            self = .all
        case "history":
            self = .history
        case "snippets":
            self = .snippets
        case "transforms":
            self = .transforms
        case "builtintransforms":
            self = .builtInTransforms
        case "customtransforms", "customtronsforms":
            self = .customTransforms
        default:
            guard normalized.hasPrefix("snippet") else {
                return nil
            }

            let suffix = normalized.dropFirst("snippet".count)
            guard let index = Int(suffix), index >= 0 else {
                return nil
            }

            self = .snippet(index)
        }
    }

    var configName: String {
        switch self {
        case .all:
            return "all"
        case .history:
            return "history"
        case .snippets:
            return "snippets"
        case .snippet(let index):
            return "snippet\(index)"
        case .transforms:
            return "transforms"
        case .builtInTransforms:
            return "builtintransforms"
        case .customTransforms:
            return "customtransforms"
        }
    }

    static func validatedConfigNames(from names: [String]) -> [String] {
        let normalized = names.compactMap { HotKeyMenuScope(configName: $0)?.configName }
        return normalized.isEmpty ? [HotKeyMenuScope.all.configName] : normalized
    }
}
