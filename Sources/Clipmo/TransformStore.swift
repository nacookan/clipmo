// 組み込み変換とカスタム正規表現変換をまとめて扱うストアです。
// 自動適用は持たず、menu からの手動実行だけに限定して作用を読みやすくしています。
import Foundation

struct CustomTransform {
    let identifier: String
    let displayName: String
    let pattern: String
    let replacement: String
    let regularExpression: NSRegularExpression
}

struct BuiltInTransform {
    let identifier: String
    let displayName: String
    let toolTip: String?
}

struct TransformApplicationResult {
    let output: String
    let didChange: Bool
}

final class TransformStore {
    private struct CustomTransformDefinition: Decodable {
        let pattern: String
        let replacement: String
        let options: TransformRegexOptions

        private enum CodingKeys: String, CodingKey {
            case pattern
            case replacement
            case options
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pattern = try container.decode(String.self, forKey: .pattern)
            replacement = try container.decode(String.self, forKey: .replacement)
            options = try container.decodeIfPresent(TransformRegexOptions.self, forKey: .options) ?? TransformRegexOptions()
        }
    }

    private var customDirectoryURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(customDirectoryURL: URL, fileManager: FileManager = .default) {
        self.customDirectoryURL = customDirectoryURL
        self.fileManager = fileManager
    }

    func updateCustomDirectoryURL(_ customDirectoryURL: URL) {
        self.customDirectoryURL = customDirectoryURL
    }

    /// 組み込み変換は regex より分かりやすい名前で前面に出し、JSON 不要の定番処理だけを持ちます。
    func builtInTransforms() -> [BuiltInTransform] {
        // regex 置換では表現しづらい「コードポイント化」や URL 系の変換は、
        // 組み込み変換として明示的に持った方が JSON も UI も単純に保てます。
        [
            BuiltInTransform(
                identifier: BuiltInTransformIdentifier.unicodeCodePoints.rawValue,
                displayName: L10n.text("transform.builtIn.unicodeCodePoints.name"),
                toolTip: L10n.text("transform.builtIn.unicodeCodePoints.tooltip")
            ),
            BuiltInTransform(
                identifier: BuiltInTransformIdentifier.utf8Bytes.rawValue,
                displayName: L10n.text("transform.builtIn.utf8Bytes.name"),
                toolTip: L10n.text("transform.builtIn.utf8Bytes.tooltip")
            ),
            BuiltInTransform(
                identifier: BuiltInTransformIdentifier.urlEncode.rawValue,
                displayName: L10n.text("transform.builtIn.urlEncode.name"),
                toolTip: L10n.text("transform.builtIn.urlEncode.tooltip")
            ),
            BuiltInTransform(
                identifier: BuiltInTransformIdentifier.urlDecode.rawValue,
                displayName: L10n.text("transform.builtIn.urlDecode.name"),
                toolTip: L10n.text("transform.builtIn.urlDecode.tooltip")
            )
        ]
    }

    /// カスタム変換はファイル名順で読み、menu の見え方と実行順を揃えます。
    func customTransforms() -> [CustomTransform] {
        customTransformFileURLs().compactMap(loadCustomTransform(from:))
    }

    func applyBuiltInTransform(identifier: String, to text: String) -> TransformApplicationResult? {
        guard let transformIdentifier = BuiltInTransformIdentifier(rawValue: identifier) else {
            return nil
        }

        let output: String
        switch transformIdentifier {
        case .unicodeCodePoints:
            output = unicodeCodePointsText(for: text)
        case .utf8Bytes:
            output = utf8BytesText(for: text)
        case .urlEncode:
            output = urlEncodedText(for: text)
        case .urlDecode:
            output = urlDecodedText(for: text)
        }

        return TransformApplicationResult(output: output, didChange: output != text)
    }

    func applyCustomTransform(identifier: String, to text: String) -> TransformApplicationResult? {
        guard let transform = customTransforms().first(where: { $0.identifier == identifier }) else {
            return nil
        }

        // カスタム変換は従来の正規表現置換 JSON をそのまま活かし、
        // 状態を持たない「手動実行だけの変換」として扱います。
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let output = transform.regularExpression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: transform.replacement
        )

        return TransformApplicationResult(output: output, didChange: output != text)
    }

    /// 置換ルール自体が壊れていても app 全体は止めず、そのファイルだけ読み飛ばします。
    private func loadCustomTransform(from fileURL: URL) -> CustomTransform? {
        do {
            let data = try Data(contentsOf: fileURL)
            let definition = try decoder.decode(CustomTransformDefinition.self, from: data)
            let regularExpression = try NSRegularExpression(
                pattern: definition.pattern,
                options: definition.options.regularExpressionOptions
            )

            return CustomTransform(
                identifier: fileURL.lastPathComponent,
                displayName: displayName(for: fileURL),
                pattern: definition.pattern,
                replacement: definition.replacement,
                regularExpression: regularExpression
            )
        } catch {
            print("Clipmo: カスタム変換の読み込みに失敗しました (\(fileURL.lastPathComponent)): \(error)")
            return nil
        }
    }

    private func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }

    private func customTransformFileURLs() -> [URL] {
        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: customDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    private func unicodeCodePointsText(for text: String) -> String {
        text.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
    }

    private func utf8BytesText(for text: String) -> String {
        text.utf8
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }

    private func urlEncodedText(for text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private func urlDecodedText(for text: String) -> String {
        text.removingPercentEncoding ?? text
    }
}

private enum BuiltInTransformIdentifier: String {
    case unicodeCodePoints
    case utf8Bytes
    case urlEncode
    case urlDecode
}

private struct TransformRegexOptions: Codable {
    var caseInsensitive: Int
    var allowCommentsAndWhitespace: Int
    var ignoreMetacharacters: Int
    var dotMatchesLineSeparators: Int
    var anchorsMatchLines: Int
    var useUnixLineSeparators: Int
    var useUnicodeWordBoundaries: Int

    private enum CodingKeys: String, CodingKey {
        case caseInsensitive
        case allowCommentsAndWhitespace
        case ignoreMetacharacters
        case dotMatchesLineSeparators
        case anchorsMatchLines
        case useUnixLineSeparators
        case useUnicodeWordBoundaries
    }

    init(
        caseInsensitive: Int = 0,
        allowCommentsAndWhitespace: Int = 0,
        ignoreMetacharacters: Int = 0,
        dotMatchesLineSeparators: Int = 0,
        anchorsMatchLines: Int = 0,
        useUnixLineSeparators: Int = 0,
        useUnicodeWordBoundaries: Int = 0
    ) {
        self.caseInsensitive = caseInsensitive
        self.allowCommentsAndWhitespace = allowCommentsAndWhitespace
        self.ignoreMetacharacters = ignoreMetacharacters
        self.dotMatchesLineSeparators = dotMatchesLineSeparators
        self.anchorsMatchLines = anchorsMatchLines
        self.useUnixLineSeparators = useUnixLineSeparators
        self.useUnicodeWordBoundaries = useUnicodeWordBoundaries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caseInsensitive = Self.decodeFlag(from: container, forKey: .caseInsensitive)
        allowCommentsAndWhitespace = Self.decodeFlag(from: container, forKey: .allowCommentsAndWhitespace)
        ignoreMetacharacters = Self.decodeFlag(from: container, forKey: .ignoreMetacharacters)
        dotMatchesLineSeparators = Self.decodeFlag(from: container, forKey: .dotMatchesLineSeparators)
        anchorsMatchLines = Self.decodeFlag(from: container, forKey: .anchorsMatchLines)
        useUnixLineSeparators = Self.decodeFlag(from: container, forKey: .useUnixLineSeparators)
        useUnicodeWordBoundaries = Self.decodeFlag(from: container, forKey: .useUnicodeWordBoundaries)
    }

    var regularExpressionOptions: NSRegularExpression.Options {
        var result: NSRegularExpression.Options = []

        if caseInsensitive != 0 {
            result.insert(.caseInsensitive)
        }

        if allowCommentsAndWhitespace != 0 {
            result.insert(.allowCommentsAndWhitespace)
        }

        if ignoreMetacharacters != 0 {
            result.insert(.ignoreMetacharacters)
        }

        if dotMatchesLineSeparators != 0 {
            result.insert(.dotMatchesLineSeparators)
        }

        if anchorsMatchLines != 0 {
            result.insert(.anchorsMatchLines)
        }

        if useUnixLineSeparators != 0 {
            result.insert(.useUnixLineSeparators)
        }

        if useUnicodeWordBoundaries != 0 {
            result.insert(.useUnicodeWordBoundaries)
        }

        return result
    }

    private static func decodeFlag(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int {
        (try? container.decode(Int.self, forKey: key)).flatMap { $0 == 0 ? 0 : 1 } ?? 0
    }
}
