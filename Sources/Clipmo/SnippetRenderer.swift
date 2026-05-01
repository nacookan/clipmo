// `.clipmo-snippet` 用の簡単なテンプレート展開を担当します。
// まずは日付だけに限定し、通常スニペットは素通しにして仕様を増やしすぎない方針です。
import Foundation

enum SnippetRenderMode {
    case plainText
    case clipmoTemplate
}

final class SnippetRenderer {
    private let dateTokenPattern = try? NSRegularExpression(pattern: #"\[\[clipmo:date:([^\]]+)\]\]"#)

    /// 普通の snippet と動的 snippet の分岐をここで吸収します。
    func render(_ text: String, mode: SnippetRenderMode, now: Date = Date()) -> String {
        switch mode {
        case .plainText:
            return text
        case .clipmoTemplate:
            return renderClipmoTemplate(text, now: now)
        }
    }

    /// token は後ろから置換して range ずれを避けます。
    private func renderClipmoTemplate(_ text: String, now: Date) -> String {
        guard let dateTokenPattern else {
            return text
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = dateTokenPattern.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return text
        }

        let result = NSMutableString(string: text)

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else {
                continue
            }

            let format = nsText.substring(with: match.range(at: 1))
            let replacement = formattedDate(format: format, now: now)
            result.replaceCharacters(in: match.range, with: replacement)
        }

        return result as String
    }

    private func formattedDate(format: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: now)
    }
}
